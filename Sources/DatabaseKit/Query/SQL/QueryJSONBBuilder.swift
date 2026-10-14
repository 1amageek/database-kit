/// Package-only postorder construction. Failed builders cannot publish a root.
package struct QueryJSONBBuilder {
    private let limits: QueryValueLimits
    private var records: [QueryJSONBStorage.Record] = []
    private var elements: [Int] = []
    private var members: [QueryJSONBStorage.Member] = []
    private var depths: [UInt64] = []
    private var parented: [Bool] = []
    private var utf8Bytes: UInt64 = 0
    private var failed = false

    package init(limits: QueryValueLimits) { self.limits = limits }

    var appendedNodeCount: UInt64 { UInt64(records.count) }

    func admitCopyTraversal(nodeCount: UInt64, depth: UInt64) throws(QueryValueError) {
        try QueryJSONParser.check(nodeCount, maximum: limits.maximumTotalNodes, resource: "nodes")
        try QueryJSONParser.check(depth, maximum: limits.maximumNestingDepth, resource: "depth")
    }

    package mutating func append(_ scalar: QueryJSONBNode) throws(QueryValueError) -> Int {
        guard !failed else { throw .nonCanonicalJSONB }
        failed = true
        try admitNode(depth: 1)
        let record: QueryJSONBStorage.Record
        switch scalar {
        case .null: record = .null
        case .bool(let value): record = .bool(value)
        case .string(let value):
            try admitString(value)
            record = .string(value)
        case .number(let value): record = .number(value)
        case .array, .object: throw .nonCanonicalJSONB
        }
        let index = appendRecord(record, depth: 1)
        failed = false
        return index
    }

    package mutating func appendArray(_ children: [Int]) throws(QueryValueError) -> Int {
        guard !failed else { throw .nonCanonicalJSONB }
        failed = true
        try admitCollection(children.count)
        var depth: UInt64 = 1
        for child in children { depth = max(depth, try claim(child)) }
        try admitNode(depth: depth)
        let start = elements.count
        elements.append(contentsOf: children)
        let index = appendRecord(.array(start..<elements.count), depth: depth)
        failed = false
        return index
    }

    package mutating func appendObject(_ children: [QueryJSONBIndexedMember]) throws(QueryValueError) -> Int {
        guard !failed else { throw .nonCanonicalJSONB }
        failed = true
        try admitCollection(children.count)
        var depth: UInt64 = 1
        var previous: String?
        for child in children {
            if let previous, QueryJSONParser.compareKeys(previous, child.key) >= 0 {
                throw .nonCanonicalJSONB
            }
            try admitString(child.key)
            previous = child.key
            depth = max(depth, try claim(child.value))
        }
        try admitNode(depth: depth)
        let start = members.count
        for child in children { members.append(.init(key: child.key, value: child.value)) }
        let index = appendRecord(.object(start..<members.count), depth: depth)
        failed = false
        return index
    }

    package consuming func finish(root: Int) throws(QueryValueError) -> QueryJSONBNode {
        guard !failed, !records.isEmpty, root == records.count - 1, !parented[root] else {
            throw .nonCanonicalJSONB
        }
        // A scalar root retains no arena; temporary builder buffers are released here.
        switch records[root] {
        case .null: return .null
        case .bool(let value): return .bool(value)
        case .string(let value): return .string(value)
        case .number(let value): return .number(value)
        case .array, .object: break
        }
        let footprint = QueryJSONBStorageFootprint(
            nodeCapacity: UInt64(records.capacity), elementIndexCapacity: UInt64(elements.capacity),
            memberCapacity: UInt64(members.capacity),
            retainedStorageByteCount: try QueryJSONBStorageFootprint.storageByteCount(
                nodeCapacity: UInt64(records.capacity), elementIndexCapacity: UInt64(elements.capacity),
                memberCapacity: UInt64(members.capacity)), utf8ByteCount: utf8Bytes
        )
        try QueryJSONParser.check(try added(footprint.retainedStorageByteCount, footprint.utf8ByteCount),
                                  maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        let storage = QueryJSONBStorage(records: records, elements: elements, members: members,
                                        footprint: footprint)
        return storage.node(at: root)
    }

    private mutating func appendRecord(_ record: QueryJSONBStorage.Record, depth: UInt64) -> Int {
        let index = records.count
        records.append(record)
        depths.append(depth)
        parented.append(false)
        return index
    }

    private func admitNode(depth: UInt64) throws(QueryValueError) {
        try QueryJSONParser.check(try added(UInt64(records.count), 1),
                                  maximum: limits.maximumTotalNodes, resource: "nodes")
        try QueryJSONParser.check(depth, maximum: limits.maximumNestingDepth, resource: "depth")
    }

    private func admitCollection(_ count: Int) throws(QueryValueError) {
        let current = try added(UInt64(elements.count), UInt64(members.count))
        try QueryJSONParser.check(try added(current, UInt64(count)),
                                  maximum: limits.maximumCollectionElements, resource: "collectionElements")
    }

    private mutating func admitString(_ value: String) throws(QueryValueError) {
        guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else { throw .nonCanonicalJSONB }
        let count = try added(utf8Bytes, UInt64(value.utf8.count))
        try QueryJSONParser.check(count, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        utf8Bytes = count
    }

    private mutating func claim(_ index: Int) throws(QueryValueError) -> UInt64 {
        guard index >= 0, index < records.count, !parented[index] else { throw .nonCanonicalJSONB }
        parented[index] = true
        return try added(depths[index], 1)
    }

    private func added(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
        let value = lhs.addingReportingOverflow(rhs)
        guard !value.overflow else { throw .arithmeticOverflow }
        return value.partialValue
    }
}
