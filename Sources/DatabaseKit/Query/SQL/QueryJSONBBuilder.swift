/// Bounded postorder construction. Failed builders cannot publish a root.
public struct QueryJSONBBuilder {
    private let limits: QueryValueLimits
    private var records: [QueryJSONBStorage.Record] = []
    private var elements: [Int] = []
    private var members: [QueryJSONBStorage.Member] = []
    private var depths: [UInt64] = []
    private var parented: [Bool] = []
    private var utf8Bytes: UInt64 = 0
    private var failed = false
    private let plannedNodeCapacity: Int?
    private let plannedElementIndexCapacity: Int?
    private let plannedMemberCapacity: Int?
    /// Canonical Array container/slot budget, including construction scratch.
    /// UTF-8 payload and allocator-internal slack are not included.
    public private(set) var constructionRetainedByteCount: UInt64


    public init(limits: QueryValueLimits) {
        self.limits = limits
        plannedNodeCapacity = nil
        plannedElementIndexCapacity = nil
        plannedMemberCapacity = nil
        constructionRetainedByteCount = Self.containerByteCount
    }

    /// Selects logical ceilings before allocating. Extra Array capacity never
    /// raises these ceilings. Callers admit and reconcile the observed budget.
    public init(limits: QueryValueLimits, nodeCapacity: Int, elementIndexCapacity: Int,
                memberCapacity: Int) throws(QueryValueError) {
        _ = try Self.constructionByteCount(nodeCapacity: nodeCapacity,
            elementIndexCapacity: elementIndexCapacity, memberCapacity: memberCapacity)
        try QueryJSONParser.check(UInt64(nodeCapacity), maximum: limits.maximumTotalNodes, resource: "nodes")
        let edges = UInt64(elementIndexCapacity).addingReportingOverflow(UInt64(memberCapacity))
        guard !edges.overflow else { throw .arithmeticOverflow }
        try QueryJSONParser.check(edges.partialValue, maximum: limits.maximumCollectionElements, resource: "collectionElements")
        let output = try QueryJSONBStorageFootprint.storageByteCount(nodeCapacity: UInt64(nodeCapacity),
            elementIndexCapacity: UInt64(elementIndexCapacity), memberCapacity: UInt64(memberCapacity))
        try QueryJSONParser.check(output, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        self.limits = limits
        plannedNodeCapacity = nodeCapacity
        plannedElementIndexCapacity = elementIndexCapacity
        plannedMemberCapacity = memberCapacity
        constructionRetainedByteCount = Self.containerByteCount
        records.reserveCapacity(nodeCapacity)
        depths.reserveCapacity(nodeCapacity)
        parented.reserveCapacity(nodeCapacity)
        elements.reserveCapacity(elementIndexCapacity)
        members.reserveCapacity(memberCapacity)
        try reconcileConstructionCapacity()
    }

    /// Canonical budget units, not an allocator/OS physical-allocation promise.
    public static func constructionByteCount(nodeCapacity: Int, elementIndexCapacity: Int,
                                             memberCapacity: Int) throws(QueryValueError) -> UInt64 {
        guard nodeCapacity >= 0, elementIndexCapacity >= 0, memberCapacity >= 0 else { throw .nonCanonicalJSONB }
        var bytes = containerByteCount
        for (capacity, stride) in [
            (nodeCapacity, MemoryLayout<QueryJSONBStorage.Record>.stride),
            (elementIndexCapacity, MemoryLayout<Int>.stride),
            (memberCapacity, MemoryLayout<QueryJSONBStorage.Member>.stride),
            (nodeCapacity, MemoryLayout<UInt64>.stride),
            (nodeCapacity, MemoryLayout<Bool>.stride),
        ] {
            let product = UInt64(capacity).multipliedReportingOverflow(by: UInt64(max(1, stride)))
            let sum = bytes.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow else { throw .arithmeticOverflow }
            bytes = sum.partialValue
        }
        return bytes
    }

    private static var containerByteCount: UInt64 {
        UInt64(MemoryLayout<[QueryJSONBStorage.Record]>.stride + MemoryLayout<[Int]>.stride
            + MemoryLayout<[QueryJSONBStorage.Member]>.stride + MemoryLayout<[UInt64]>.stride
            + MemoryLayout<[Bool]>.stride)
    }

    private mutating func reconcileConstructionCapacity() throws(QueryValueError) {
        // Scratch arrays can have different observed capacities despite one
        // logical node ceiling. Charge every container and observed slot.
        var bytes = try Self.constructionByteCount(nodeCapacity: records.capacity,
            elementIndexCapacity: elements.capacity, memberCapacity: members.capacity)
        let assumedScratch = UInt64(records.capacity).multipliedReportingOverflow(
            by: UInt64(MemoryLayout<UInt64>.stride + MemoryLayout<Bool>.stride))
        guard !assumedScratch.overflow else { throw .arithmeticOverflow }
        bytes -= assumedScratch.partialValue
        let depthBytes = UInt64(depths.capacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<UInt64>.stride))
        let parentBytes = UInt64(parented.capacity).multipliedReportingOverflow(by: UInt64(MemoryLayout<Bool>.stride))
        let sum = bytes.addingReportingOverflow(depthBytes.partialValue)
        let total = sum.partialValue.addingReportingOverflow(parentBytes.partialValue)
        guard !depthBytes.overflow, !parentBytes.overflow, !sum.overflow, !total.overflow else { throw .arithmeticOverflow }
        constructionRetainedByteCount = total.partialValue
    }

    var appendedNodeCount: UInt64 { UInt64(records.count) }

    func admitCopyTraversal(nodeCount: UInt64, depth: UInt64) throws(QueryValueError) {
        try QueryJSONParser.check(nodeCount, maximum: limits.maximumTotalNodes, resource: "nodes")
        try QueryJSONParser.check(depth, maximum: limits.maximumNestingDepth, resource: "depth")
    }

    public mutating func append(_ scalar: QueryJSONBNode) throws(QueryValueError) -> Int {
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
        let index = try appendRecord(record, depth: 1)
        failed = false
        return index
    }

    public mutating func appendArray(_ children: [Int]) throws(QueryValueError) -> Int {
        guard !failed else { throw .nonCanonicalJSONB }
        failed = true
        try admitCollection(children.count)
        try admitPlanned(try added(UInt64(elements.count), UInt64(children.count)),
                         maximum: plannedElementIndexCapacity, resource: "jsonbPlannedElementIndexCapacity")
        var depth: UInt64 = 1
        for child in children { depth = max(depth, try claim(child)) }
        try admitNode(depth: depth)
        let start = elements.count
        elements.append(contentsOf: children)
        let index = try appendRecord(.array(start..<elements.count), depth: depth)
        failed = false
        return index
    }

    public mutating func appendObject(_ children: [QueryJSONBIndexedMember]) throws(QueryValueError) -> Int {
        guard !failed else { throw .nonCanonicalJSONB }
        failed = true
        try admitCollection(children.count)
        try admitPlanned(try added(UInt64(members.count), UInt64(children.count)),
                         maximum: plannedMemberCapacity, resource: "jsonbPlannedMemberCapacity")
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
        let index = try appendRecord(.object(start..<members.count), depth: depth)
        failed = false
        return index
    }

    public consuming func finish(root: Int) throws(QueryValueError) -> QueryJSONBNode {
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

    private mutating func appendRecord(_ record: QueryJSONBStorage.Record, depth: UInt64) throws(QueryValueError) -> Int {
        let index = records.count
        records.append(record)
        depths.append(depth)
        parented.append(false)
        try reconcileConstructionCapacity()
        return index
    }

    private func admitPlanned(_ actual: UInt64, maximum: Int?, resource: String) throws(QueryValueError) {
        if let maximum { try QueryJSONParser.check(actual, maximum: UInt64(maximum), resource: resource) }
    }

    private func admitNode(depth: UInt64) throws(QueryValueError) {
        try admitPlanned(try added(UInt64(records.count), 1), maximum: plannedNodeCapacity,
                         resource: "jsonbPlannedNodeCapacity")
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
