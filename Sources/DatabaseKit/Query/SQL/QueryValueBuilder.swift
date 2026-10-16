import DatabaseTypes

/// Task-local postorder construction; final storage contains indices, never child owners.
public struct QueryValueBuilder {
    private enum ImportFrame {
        case array(QueryArrayValue, Range<Int>, Int)
        case composite(QueryCompositeValue, Range<Int>, Int)
    }

    private let limits: QueryValueLimits
    private let planned: (nodes: Int, children: Int, dimensions: Int)?
    private var records: [QueryValueStorage.Record] = []
    private var children: [Int] = []
    private var dimensions: [QueryArrayDimension] = []
    private var parented: [Bool] = []
    private var types: QueryTypeBuilder
    private var leafBytes: UInt64 = 0
    private var utf8Bytes: UInt64 = 0
    private var failed = false
    private var leafRetentionIsAdmitted = false
    private var hasCollection = false
    private var importScratchBytes: UInt64 = 0
    public private(set) var constructionRetainedByteCount: UInt64 = 0

    public init(limits: QueryValueLimits) {
        self.limits = limits; planned = nil; types = QueryTypeBuilder(limits: limits)
        constructionRetainedByteCount = Self.containerBytes
    }

    /// The reader has admitted shared frame and leaf owners with its enclosing ledger.
    package init(admittedLimits: QueryValueLimits) {
        self.init(limits: admittedLimits)
        leafRetentionIsAdmitted = true
    }

    public init(limits: QueryValueLimits, nodeCapacity: Int, childIndexCapacity: Int,
                dimensionCapacity: Int, typeNodeCapacity: Int, columnCapacity: Int) throws(QueryValueError) {
        _ = try Self.constructionByteCount(nodeCapacity: nodeCapacity, childIndexCapacity: childIndexCapacity,
            dimensionCapacity: dimensionCapacity, typeNodeCapacity: typeNodeCapacity, columnCapacity: columnCapacity)
        try QueryValueAccounting.check(UInt64(nodeCapacity), limits.maximumTotalNodes, "nodes")
        try QueryValueAccounting.check(UInt64(childIndexCapacity), limits.maximumCollectionElements, "collectionElements")
        let selectedStorage = try QueryValueAccounting.add(
            Self.storageBytes(nodes: nodeCapacity, children: childIndexCapacity, dimensions: dimensionCapacity),
            QueryTypeBuilder.storageBytes(nodes: typeNodeCapacity, columns: columnCapacity))
        try QueryValueAccounting.check(selectedStorage, limits.maximumRetainedBytes, "retainedBytes")
        self.limits = limits
        planned = (nodeCapacity, childIndexCapacity, dimensionCapacity)
        types = try QueryTypeBuilder(limits: limits, typeNodeCapacity: typeNodeCapacity, columnCapacity: columnCapacity)
        try QueryValueAccounting.check(Self.storageBytes(nodes: nodeCapacity, children: childIndexCapacity,
            dimensions: dimensionCapacity), limits.maximumRetainedBytes, "retainedBytes")
        records.reserveCapacity(nodeCapacity); children.reserveCapacity(childIndexCapacity)
        dimensions.reserveCapacity(dimensionCapacity); parented.reserveCapacity(nodeCapacity)
        try reconcile()
    }

    private static var containerBytes: UInt64 {
        UInt64(MemoryLayout<[QueryValueStorage.Record]>.stride + MemoryLayout<[Int]>.stride
            + MemoryLayout<[QueryArrayDimension]>.stride + MemoryLayout<[Bool]>.stride)
    }

    private static func storageBytes(nodes: Int, children: Int, dimensions: Int) throws(QueryValueError) -> UInt64 {
        var result = UInt64(MemoryLayout<[QueryValueStorage.Record]>.stride + MemoryLayout<[Int]>.stride
            + MemoryLayout<[QueryArrayDimension]>.stride)
        result = try QueryValueAccounting.add(result, QueryValueAccounting.slots(nodes, stride: MemoryLayout<QueryValueStorage.Record>.stride))
        result = try QueryValueAccounting.add(result, QueryValueAccounting.slots(children, stride: MemoryLayout<Int>.stride))
        return try QueryValueAccounting.add(result, QueryValueAccounting.slots(dimensions, stride: MemoryLayout<QueryArrayDimension>.stride))
    }

    public static func constructionByteCount(nodeCapacity: Int, childIndexCapacity: Int,
        dimensionCapacity: Int, typeNodeCapacity: Int, columnCapacity: Int) throws(QueryValueError) -> UInt64 {
        var result = try storageBytes(nodes: nodeCapacity, children: childIndexCapacity, dimensions: dimensionCapacity)
        result = try QueryValueAccounting.add(result, QueryValueAccounting.slots(nodeCapacity,
            stride: MemoryLayout<Bool>.stride + MemoryLayout<ImportFrame>.stride))
        result = try QueryValueAccounting.add(result, UInt64(MemoryLayout<[Bool]>.stride + MemoryLayout<[ImportFrame]>.stride))
        return try QueryValueAccounting.add(result, QueryTypeBuilder.constructionByteCount(
            typeNodeCapacity: typeNodeCapacity, columnCapacity: columnCapacity))
    }

    public mutating func append(_ value: QueryValue) throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }
        failed = true
        var current = value
        var frames: [ImportFrame] = []
        while true {
            let completed: Int
            switch current {
            case .array(let source):
                let range = try reserveChildren(source.elements.count)
                if !range.isEmpty {
                    try admitImportFrame(frames.count + 1)
                    frames.append(.array(source, range, 0))
                    current = source.elements[0]
                    continue
                }
                completed = try appendArray(source.elementType, dimensions: Array(source.dimensions), range: range)
            case .composite(let source):
                let range = try reserveChildren(source.fields.count)
                if !range.isEmpty {
                    try admitImportFrame(frames.count + 1)
                    frames.append(.composite(source, range, 0))
                    current = source.fields[0]
                    continue
                }
                completed = try appendComposite(source.type, range: range)
            default: completed = try appendScalar(current)
            }
            var result = completed
            var descend = false
            while let frame = frames.popLast() {
                switch frame {
                case .array(let source, let range, let index):
                    children[range.lowerBound + index] = result
                    if index + 1 < range.count {
                        frames.append(.array(source, range, index + 1)); current = source.elements[index + 1]; descend = true
                    } else { result = try appendArray(source.elementType, dimensions: Array(source.dimensions), range: range) }
                case .composite(let source, let range, let index):
                    children[range.lowerBound + index] = result
                    if index + 1 < range.count {
                        frames.append(.composite(source, range, index + 1)); current = source.fields[index + 1]; descend = true
                    } else { result = try appendComposite(source.type, range: range) }
                }
                if descend { break }
            }
            importScratchBytes = max(importScratchBytes,
                try QueryValueAccounting.slots(frames.capacity, stride: MemoryLayout<ImportFrame>.stride))
            try reconcile()
            if !descend { failed = false; return result }
        }
    }

    public mutating func appendArray(elementType: DataType, dimensions: [QueryArrayDimension], elements: [Int])
        throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }
        failed = true
        let range = try reserveChildren(elements.count)
        for (offset, child) in elements.enumerated() { children[range.lowerBound + offset] = child }
        let result = try appendArray(elementType, dimensions: dimensions, range: range)
        try reconcile(); failed = false
        return result
    }

    public mutating func appendComposite(type: QueryCompositeType, fields: [Int]) throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }
        failed = true
        let range = try reserveChildren(fields.count)
        for (offset, child) in fields.enumerated() { children[range.lowerBound + offset] = child }
        let result = try appendComposite(type, range: range)
        try reconcile(); failed = false
        return result
    }

    private mutating func appendScalar(_ value: QueryValue) throws(QueryValueError) -> Int {
        let kind: QueryValueStorage.Kind
        switch value {
        case .primitive(let x): kind = .primitive(x)
        case .numeric(let x): kind = .numeric(x)
        case .json(let x): kind = .json(x)
        case .jsonb(let x): kind = .jsonb(x)
        case .interval(let x): kind = .interval(x)
        case .time(let x): kind = .time(x)
        case .timeWithTimeZone(let x): kind = .timeWithTimeZone(x)
        case .dateInfinity(let x): kind = .dateInfinity(x)
        case .timestampInfinity(let x, let zone): kind = .timestampInfinity(x, zone)
        case .intervalInfinity(let x): kind = .intervalInfinity(x)
        case .array, .composite: throw .invalidValueConstruction
        }
        let logical = try QueryValueValidator.measure(value)
        let retained = try QueryValueAccounting.add(leafBytes, logical.retainedByteCount)
        if !leafRetentionIsAdmitted {
            try QueryValueAccounting.check(retained, limits.maximumRetainedBytes, "retainedBytes")
        }
        leafBytes = retained
        if case .primitive(let field) = value {
            var meter = QueryFieldStorageMeter(); try meter.field(field, depth: 1)
            utf8Bytes = try QueryValueAccounting.add(utf8Bytes, meter.footprint.newUTF8Bytes)
        } else if case .jsonb(let jsonb) = value {
            utf8Bytes = try QueryValueAccounting.add(utf8Bytes, jsonb.root.storageFootprint.utf8ByteCount)
        }
        return try appendRecord(kind, logical: logical)
    }

    private mutating func appendArray(_ elementType: DataType, dimensions shape: [QueryArrayDimension], range: Range<Int>)
        throws(QueryValueError) -> Int {
        hasCollection = true
        try QueryArrayValue.validateShape(elementType: elementType, dimensions: shape, count: range.count)
        for (offset, edge) in range.enumerated() {
            let id = children[edge]
            try validateReference(id)
            guard accepts(id, type: .sql(elementType)) else { throw .elementTypeMismatch(index: UInt64(offset)) }
        }
        let next = try QueryValueAccounting.add(UInt64(dimensions.count), UInt64(shape.count))
        if let planned { try QueryValueAccounting.check(next, UInt64(planned.dimensions), "queryPlannedDimensionCapacity") }
        try admitStorage(nodes: records.count + 1, children: children.count, dimensions: QueryValueAccounting.integer(next))
        let start = dimensions.count; dimensions.append(contentsOf: shape)
        let type = try types.append(type: .sql(elementType))
        let values = try claimChildren(range)
        let metadata: QueryValueFootprint
        if case .composite = elementType { metadata = types.records[type].logical }
        else { metadata = QueryValueFootprint(nodeCount: 0, collectionElementCount: 0, retainedByteCount: 0, maximumNestingDepth: 0) }
        let logical = QueryValueFootprint(nodeCount: try QueryValueAccounting.add(values.nodeCount, metadata.nodeCount),
            collectionElementCount: try QueryValueAccounting.add(values.collectionElementCount, metadata.collectionElementCount), retainedByteCount: 0,
            maximumNestingDepth: max(values.maximumNestingDepth,
                try QueryValueAccounting.add(types.records[type].logical.maximumNestingDepth, 1)))
        return try appendRecord(.array(type: type, dimensions: start..<dimensions.count, elements: range), logical: logical)
    }

    private mutating func appendComposite(_ type: QueryCompositeType, range: Range<Int>) throws(QueryValueError) -> Int {
        hasCollection = true
        guard range.count == type.columns.count else {
            throw .compositeFieldCountMismatch(expected: UInt64(type.columns.count), actual: UInt64(range.count))
        }
        for (offset, edge) in range.enumerated() {
            let id = children[edge]; try validateReference(id)
            let column = type.columns[offset]
            if !column.isNullable, isNull(id) { throw .nullCompositeField(index: UInt64(offset)) }
            guard accepts(id, type: column.type) else { throw .elementTypeMismatch(index: UInt64(offset)) }
        }
        let descriptor = try types.append(type: .sql(.composite(type)))
        let values = try claimChildren(range)
        let metadata = types.records[descriptor].logical
        let logical = QueryValueFootprint(nodeCount: try QueryValueAccounting.add(values.nodeCount, metadata.nodeCount),
            collectionElementCount: try QueryValueAccounting.add(values.collectionElementCount, metadata.collectionElementCount), retainedByteCount: 0,
            maximumNestingDepth: max(values.maximumNestingDepth,
                try QueryValueAccounting.add(types.records[descriptor].logical.maximumNestingDepth, 1)))
        return try appendRecord(.composite(type: descriptor, fields: range), logical: logical)
    }

    private func isNull(_ id: Int) -> Bool {
        if case .primitive(.null) = records[id].kind { return true }
        return false
    }

    private func accepts(_ id: Int, type: QueryColumnType) -> Bool {
        if isNull(id) { return QueryValueValidator.accepts(.primitive(.null), type: type) }
        switch records[id].kind {
        case .array(let element, _, _):
            guard case .sql(.array(let expected)) = type else { return false }
            return types.matches(element, type: .sql(expected))
        case .composite(let actual, _): return types.matches(actual, type: type)
        default: return QueryValueValidator.accepts(scalar(at: id), type: type)
        }
    }

    private func scalar(at index: Int) -> QueryValue {
        switch records[index].kind {
        case .primitive(let x): .primitive(x)
        case .numeric(let x): .numeric(x)
        case .json(let x): .json(x)
        case .jsonb(let x): .jsonb(x)
        case .interval(let x): .interval(x)
        case .time(let x): .time(x)
        case .timeWithTimeZone(let x): .timeWithTimeZone(x)
        case .dateInfinity(let x): .dateInfinity(x)
        case .timestampInfinity(let x, let zone): .timestampInfinity(x, withTimeZone: zone)
        case .intervalInfinity(let x): .intervalInfinity(x)
        case .array, .composite: preconditionFailure("A scalar record cannot own a SQL collection")
        }
    }

    private func validateReference(_ index: Int) throws(QueryValueError) {
        guard records.indices.contains(index), !parented[index] else { throw .invalidBuilderReference(index: index) }
    }

    private mutating func claimChildren(_ range: Range<Int>) throws(QueryValueError) -> QueryValueFootprint {
        var nodes: UInt64 = 1; var elements = UInt64(range.count); var depth: UInt64 = 1
        for edge in range {
            let id = children[edge]; try validateReference(id)
            parented[id] = true
            let child = records[id].logical
            nodes = try QueryValueAccounting.add(nodes, child.nodeCount)
            elements = try QueryValueAccounting.add(elements, child.collectionElementCount)
            depth = max(depth, try QueryValueAccounting.add(child.maximumNestingDepth, 1))
        }
        return QueryValueFootprint(nodeCount: nodes, collectionElementCount: elements,
                                   retainedByteCount: 0, maximumNestingDepth: depth)
    }

    private mutating func reserveChildren(_ count: Int) throws(QueryValueError) -> Range<Int> {
        let total = try QueryValueAccounting.add(UInt64(children.count), UInt64(count))
        try QueryValueAccounting.check(total, limits.maximumCollectionElements, "collectionElements")
        if let planned { try QueryValueAccounting.check(total, UInt64(planned.children), "queryPlannedChildIndexCapacity") }
        try admitStorage(nodes: records.count, children: QueryValueAccounting.integer(total), dimensions: dimensions.count, forCollection: true)
        let start = children.count
        children.append(contentsOf: repeatElement(-1, count: count))
        return start..<children.count
    }

    private mutating func appendRecord(_ kind: QueryValueStorage.Kind, logical: QueryValueFootprint)
        throws(QueryValueError) -> Int {
        let count = try QueryValueAccounting.add(UInt64(records.count), 1)
        try QueryValueAccounting.check(count, limits.maximumTotalNodes, "nodes")
        if let planned { try QueryValueAccounting.check(count, UInt64(planned.nodes), "queryPlannedNodeCapacity") }
        try logical.validate(limits: limits)
        try admitStorage(nodes: QueryValueAccounting.integer(count), children: children.count, dimensions: dimensions.count)
        let index = records.count
        records.append(.init(kind: kind, logical: logical)); parented.append(false)
        try reconcile()
        return index
    }

    private mutating func admitImportFrame(_ count: Int) throws(QueryValueError) {
        try QueryValueAccounting.check(UInt64(count + 1), limits.maximumNestingDepth, "depth")
    }

    private func admitStorage(nodes: Int, children: Int, dimensions: Int, forCollection: Bool = false) throws(QueryValueError) {
        if !hasCollection && !forCollection {
            if !leafRetentionIsAdmitted { try QueryValueAccounting.check(leafBytes, limits.maximumRetainedBytes, "retainedBytes") }
            return
        }
        let type = try types.footprint
        var bytes = try Self.storageBytes(nodes: nodes, children: children, dimensions: dimensions)
        if !leafRetentionIsAdmitted { bytes = try QueryValueAccounting.add(bytes, leafBytes) }
        bytes = try QueryValueAccounting.add(bytes, QueryValueAccounting.add(type.retainedStorageByteCount, type.utf8ByteCount))
        try QueryValueAccounting.check(bytes, limits.maximumRetainedBytes, "retainedBytes")
    }

    private mutating func reconcile() throws(QueryValueError) {
        try QueryValueAccounting.check(QueryValueAccounting.add(UInt64(records.count),
            QueryValueAccounting.add(UInt64(types.records.count), UInt64(types.columns.count))), limits.maximumTotalNodes, "nodes")
        try QueryValueAccounting.check(QueryValueAccounting.add(UInt64(children.count), UInt64(types.columns.count)),
                                       limits.maximumCollectionElements, "collectionElements")
        try admitStorage(nodes: records.capacity, children: children.capacity, dimensions: dimensions.capacity)
        let storage = try Self.storageBytes(nodes: records.capacity, children: children.capacity, dimensions: dimensions.capacity)
        let parent = try QueryValueAccounting.slots(parented.capacity, stride: MemoryLayout<Bool>.stride)
        let type = try types.footprint
        constructionRetainedByteCount = try QueryValueAccounting.add(
            QueryValueAccounting.add(storage, parent), QueryValueAccounting.add(
                QueryValueAccounting.add(type.retainedStorageByteCount, types.scratchByteHighWater),
                QueryValueAccounting.add(importScratchBytes, UInt64(MemoryLayout<[Bool]>.stride + MemoryLayout<[ImportFrame]>.stride))))
    }

    public consuming func finish(root: Int) throws(QueryValueError) -> QueryValue {
        guard !failed, records.indices.contains(root), root == records.count - 1, !parented[root],
              parented.dropLast().allSatisfy({ $0 }) else { throw .invalidValueConstruction }
        try reconcile()
        switch records[root].kind {
        case .array, .composite: break
        default: return scalar(at: root)
        }
        let footprint = QueryValueStorageFootprint(nodeCapacity: UInt64(records.capacity),
            childIndexCapacity: UInt64(children.capacity), dimensionCapacity: UInt64(dimensions.capacity),
            retainedStorageByteCount: try Self.storageBytes(nodes: records.capacity, children: children.capacity, dimensions: dimensions.capacity),
            utf8ByteCount: utf8Bytes, leafRetainedByteCount: leafBytes, typeStorageFootprint: try types.footprint)
        if !leafRetentionIsAdmitted {
            try QueryValueAccounting.check(footprint.retainedByteCount, limits.maximumRetainedBytes, "retainedBytes")
        }
        let typeStorage = try types.finish()
        return QueryValueStorage(records: records, children: children, dimensions: dimensions,
                                 types: typeStorage, footprint: footprint).value(at: root)
    }
}
