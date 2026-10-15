/// Request-local semantic occurrence identities and parent-edge lookup.
///
/// Values with equal payloads retain distinct identities under distinct edges.
/// The arena owns no source positions. Pass it together with the selected root;
/// indices from a different arena have no meaning here.
public struct QueryOccurrenceArena: Sendable {
    private struct Address: Sendable, Hashable {
        let parent: QueryOccurrenceID?
        let field: QueryOccurrenceField
        let index: UInt32?
    }

    public private(set) var occurrences: [QueryOccurrence] = []
    private var addresses: [Address: QueryOccurrenceID] = [:]
    private var ledger: QueryStructuralResourceLedger

    public init(limits: QueryStructuralLimits = .default) {
        ledger = QueryStructuralResourceLedger(limits: limits)
    }

    public var count: Int { occurrences.count }

    /// Logical declaration storage budget; allocator capacity is runtime-owned.
    public var remainingLimits: QueryStructuralLimits { ledger.remainingLimits }

    public func occurrence(_ id: QueryOccurrenceID) -> QueryOccurrence? {
        guard let index = Int(exactly: id.rawValue), occurrences.indices.contains(index) else { return nil }
        return occurrences[index]
    }

    public func child(
        of parent: QueryOccurrenceID,
        field: QueryOccurrenceField,
        index: UInt32? = nil
    ) -> QueryOccurrenceID? {
        addresses[Address(parent: parent, field: field, index: index)]
    }

    /// Admits the node and its lookup edge before growing either collection.
    public mutating func append(
        parent: QueryOccurrenceID? = nil,
        field: QueryOccurrenceField = .statement,
        index: UInt32? = nil
    ) throws(QueryOccurrenceError) -> QueryOccurrenceID {
        let depth: UInt64
        if let parent {
            guard let occurrence = occurrence(parent) else { throw .invalidParent(parent) }
            let next = occurrence.depth.addingReportingOverflow(1)
            guard !next.overflow else { throw .identifierOverflow }
            depth = next.partialValue
        } else {
            depth = 0
        }
        let address = Address(parent: parent, field: field, index: index)
        guard addresses[address] == nil else { throw .duplicateOccurrence }
        guard let rawValue = UInt32(exactly: occurrences.count) else { throw .identifierOverflow }
        var admission = ledger
        do {
            try admission.validateNestingDepth(depth)
            try admission.consume(.totalNodes)
            try admission.consume(.collectionElements, amount: parent == nil ? 0 : 1)
            // This logical charge covers the node and lookup record. It does not
            // measure Array/Dictionary allocator capacity or runtime plan storage.
            let bytes = MemoryLayout<QueryOccurrence>.stride
                + MemoryLayout<Address>.stride + MemoryLayout<QueryOccurrenceID>.stride
            try admission.consume(.retainedBytes, amount: UInt64(bytes))
        } catch {
            throw .resourceLimit(error)
        }
        let id = QueryOccurrenceID(rawValue: rawValue)
        occurrences.append(QueryOccurrence(parent: parent, field: field, index: index, depth: depth))
        addresses[address] = id
        ledger = admission
        return id
    }
}
