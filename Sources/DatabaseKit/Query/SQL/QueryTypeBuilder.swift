import DatabaseTypes

package struct QueryTypeBuilder {
    enum Columns {
        case owned([QueryColumn])
        case view(QueryCompositeColumns)
        var count: Int {
            switch self { case .owned(let x): x.count; case .view(let x): x.count }
        }
        subscript(index: Int) -> QueryColumn {
            switch self { case .owned(let x): x[index]; case .view(let x): x[index] }
        }
    }

    private enum Step {
        case type(QueryColumnType)
        case columns(Columns)
        case column(Columns, Range<Int>, Int)
        case storeColumn(Columns, Range<Int>, Int)
        case finishComposite(Range<Int>)
        case finishArray
        case cacheComposite(QueryCompositeType)
    }

    private struct Origin {
        let owner: QueryTypeStorage
        let index: Int
        let destination: Int
    }

    let limits: QueryValueLimits
    private(set) var records: [QueryTypeStorage.Record] = []
    private(set) var columns: [QueryTypeStorage.Column] = []
    private var origins: [Origin] = []
    private var failed = false
    private var utf8Bytes: UInt64 = 0
    private let plannedNodes: Int?
    private let plannedColumns: Int?
    private(set) var scratchByteHighWater: UInt64 = 0

    package init(limits: QueryValueLimits) {
        self.limits = limits; plannedNodes = nil; plannedColumns = nil
    }

    init(limits: QueryValueLimits, typeNodeCapacity: Int, columnCapacity: Int) throws(QueryValueError) {
        _ = try Self.constructionByteCount(typeNodeCapacity: typeNodeCapacity, columnCapacity: columnCapacity)
        try QueryValueAccounting.check(UInt64(typeNodeCapacity), limits.maximumTotalNodes, "nodes")
        try QueryValueAccounting.check(UInt64(columnCapacity), limits.maximumCollectionElements, "collectionElements")
        self.limits = limits; plannedNodes = typeNodeCapacity; plannedColumns = columnCapacity
        try QueryValueAccounting.check(Self.storageBytes(nodes: typeNodeCapacity, columns: columnCapacity),
                                       limits.maximumRetainedBytes, "retainedBytes")
        records.reserveCapacity(typeNodeCapacity); columns.reserveCapacity(columnCapacity)
        try checkStorage()
    }

    static func storageBytes(nodes: Int, columns: Int) throws(QueryValueError) -> UInt64 {
        try QueryValueAccounting.add(
            UInt64(MemoryLayout<[QueryTypeStorage.Record]>.stride + MemoryLayout<[QueryTypeStorage.Column]>.stride),
            QueryValueAccounting.add(QueryValueAccounting.slots(nodes, stride: MemoryLayout<QueryTypeStorage.Record>.stride),
                                     QueryValueAccounting.slots(columns, stride: MemoryLayout<QueryTypeStorage.Column>.stride)))
    }

    static func constructionByteCount(typeNodeCapacity: Int, columnCapacity: Int) throws(QueryValueError) -> UInt64 {
        let storage = try storageBytes(nodes: typeNodeCapacity, columns: columnCapacity)
        let frames = try QueryValueAccounting.slots(typeNodeCapacity,
            stride: MemoryLayout<Step>.stride * 3 + MemoryLayout<Int>.stride + MemoryLayout<Origin>.stride)
        return try QueryValueAccounting.add(storage, QueryValueAccounting.add(frames,
            UInt64(MemoryLayout<[Step]>.stride + MemoryLayout<[Int]>.stride + MemoryLayout<[Origin]>.stride)))
    }

    var footprint: QueryTypeStorageFootprint {
        get throws(QueryValueError) {
            QueryTypeStorageFootprint(typeNodeCapacity: UInt64(records.capacity), columnCapacity: UInt64(columns.capacity),
                retainedStorageByteCount: try Self.storageBytes(nodes: records.capacity, columns: columns.capacity),
                utf8ByteCount: utf8Bytes)
        }
    }

    private enum Match {
        case type(Int, QueryColumnType)
        case columns(Range<Int>, QueryCompositeColumns, Int)
    }

    func matches(_ index: Int, type: QueryColumnType) -> Bool {
        var work: [Match] = [.type(index, type)]
        while let entry = work.popLast() {
            switch entry {
            case .type(let id, let expected):
                switch (records[id].kind, expected) {
                case (.primitive(let kind, let array), .primitive(let other, let otherArray)):
                    guard kind == other, array == otherArray else { return false }
                case (.array(let child), .sql(.array(let other))): work.append(.type(child, .sql(other)))
                case (.composite(let range), .sql(.composite(let other))):
                    guard range.count == other.columns.count else { return false }
                    if !range.isEmpty { work.append(.columns(range, other.columns, 0)) }
                case (let actual, .sql(let other)):
                    do throws(QueryValueError) { guard actual == (try Self.scalar(other)) else { return false } }
                    catch { return false }
                default: return false
                }
            case .columns(let range, let other, let i):
                let a = columns[range.lowerBound + i], b = other[i]
                guard a.number == b.number, a.name.utf8.elementsEqual(b.name.utf8),
                      a.isNullable == b.isNullable else { return false }
                if i + 1 < range.count { work.append(.columns(range, other, i + 1)) }
                work.append(.type(a.type, b.type))
            }
        }
        return true
    }

    mutating func append(type: QueryColumnType) throws(QueryValueError) -> Int {
        try Self.logical(type).validate(limits: limits)
        return try run(.type(type))
    }
    mutating func append(columns input: Columns) throws(QueryValueError) -> Int {
        var nodes: UInt64 = 1; var edges = UInt64(input.count); var depth: UInt64 = 1
        for i in 0..<input.count {
            let child = try Self.logical(input[i].type)
            nodes = try QueryValueAccounting.add(nodes, QueryValueAccounting.add(child.nodeCount, 1))
            edges = try QueryValueAccounting.add(edges, child.collectionElementCount)
            depth = max(depth, try QueryValueAccounting.add(child.maximumNestingDepth, 2))
        }
        try QueryValueFootprint(nodeCount: nodes, collectionElementCount: edges, retainedByteCount: 0,
                                maximumNestingDepth: depth).validate(limits: limits)
        return try run(.columns(input))
    }

    private static func logical(_ type: QueryColumnType) throws(QueryValueError) -> QueryValueFootprint {
        if case .sql(.composite(let value)) = type { return value.storage.records[value.index].logical }
        if case .sql(.array(let child)) = type {
            if case .array = child { throw .incompatibleType }
            let inner: QueryValueFootprint
            if case .composite(let value) = child { inner = value.storage.records[value.index].logical }
            else { inner = QueryValueFootprint(nodeCount: 1, collectionElementCount: 0, retainedByteCount: 0, maximumNestingDepth: 1) }
            return QueryValueFootprint(nodeCount: try QueryValueAccounting.add(inner.nodeCount, 1),
                collectionElementCount: try QueryValueAccounting.add(inner.collectionElementCount, 1),
                retainedByteCount: 0, maximumNestingDepth: try QueryValueAccounting.add(inner.maximumNestingDepth, 1))
        }
        return QueryValueFootprint(nodeCount: 1, collectionElementCount: 0, retainedByteCount: 0, maximumNestingDepth: 1)
    }

    package mutating func append(_ scalar: QueryColumnType) throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }; failed = true
        if case .sql(let type) = scalar {
            switch type { case .array, .composite: throw .incompatibleType; default: break }
        }
        let result = try append(type: scalar)
        failed = false; return result
    }

    package mutating func appendArray(element: Int) throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }; failed = true
        guard records.indices.contains(element) else { throw .invalidBuilderReference(index: element) }
        switch records[element].kind {
        case .primitive, .array: throw .incompatibleType
        default: break
        }
        let source = records[element].logical
        let result = try appendRecord(.array(element), logical: QueryValueFootprint(
            nodeCount: QueryValueAccounting.add(source.nodeCount, 1),
            collectionElementCount: QueryValueAccounting.add(source.collectionElementCount, 1),
            retainedByteCount: 0, maximumNestingDepth: QueryValueAccounting.add(source.maximumNestingDepth, 1)))
        try checkStorage(); failed = false; return result
    }

    package mutating func appendComposite(columns input: [QueryTypeColumn]) throws(QueryValueError) -> Int {
        guard !failed else { throw .invalidValueConstruction }; failed = true
        let next = try QueryValueAccounting.add(UInt64(columns.count), UInt64(input.count))
        try QueryValueAccounting.check(next, limits.maximumCollectionElements, "collectionElements")
        try planned(next, plannedColumns, "queryPlannedColumnCapacity")
        var names = utf8Bytes
        for (index, column) in input.enumerated() {
            guard UInt64(column.number) == UInt64(index) + 1 else { throw .invalidColumnNumber(column.number) }
            guard records.indices.contains(column.type) else { throw .invalidBuilderReference(index: column.type) }
            names = try QueryValueAccounting.add(names, UInt64(column.name.utf8.count))
        }
        try admitStorage(nodes: records.count, columns: QueryValueAccounting.integer(next), utf8: names)
        let start = columns.count
        columns.reserveCapacity(try QueryValueAccounting.integer(next))
        for column in input {
            columns.append(.init(number: column.number, name: column.name, type: column.type, isNullable: column.isNullable))
        }
        utf8Bytes = names
        let range = start..<columns.count
        var nodes: UInt64 = 1; var edges = UInt64(range.count); var depth: UInt64 = 1
        for index in range {
            let child = records[columns[index].type].logical
            nodes = try QueryValueAccounting.add(nodes, QueryValueAccounting.add(child.nodeCount, 1))
            edges = try QueryValueAccounting.add(edges, child.collectionElementCount)
            depth = max(depth, try QueryValueAccounting.add(child.maximumNestingDepth, 2))
        }
        let root = try appendRecord(.composite(range), logical: QueryValueFootprint(nodeCount: nodes,
            collectionElementCount: edges, retainedByteCount: 0, maximumNestingDepth: depth))
        try checkStorage(); failed = false
        return root
    }

    package consuming func finish(root: Int) throws(QueryValueError) -> DataType {
        guard !failed else { throw .invalidValueConstruction }
        guard records.indices.contains(root) else { throw .invalidBuilderReference(index: root) }
        let storage = try finish()
        guard case .sql(let type) = storage.type(at: root) else { throw .incompatibleType }
        return type
    }

    private mutating func run(_ first: Step) throws(QueryValueError) -> Int {
        var work = [first]
        var results: [Int] = []
        while let step = work.popLast() {
            switch step {
            case .type(let type):
                switch type {
                case .primitive(let kind, let array):
                    results.append(try appendRecord(.primitive(kind, array), logical: scalarLogical))
                case .sql(.array(let child)):
                    if case .array = child { throw .incompatibleType }
                    work.append(.finishArray); work.append(.type(.sql(child)))
                case .sql(.composite(let type)):
                    if let existing = origins.first(where: { $0.owner === type.storage && $0.index == type.index }) {
                        results.append(existing.destination)
                    } else {
                        work.append(.cacheComposite(type))
                        work.append(.columns(.view(type.columns)))
                    }
                case .sql(let scalar):
                    guard QueryValueValidator.accepts(.primitive(.null), type: .sql(scalar)) else { throw .incompatibleType }
                    results.append(try appendRecord(Self.scalar(scalar), logical: scalarLogical))
                }
            case .columns(let input):
                let next = try QueryValueAccounting.add(UInt64(columns.count), UInt64(input.count))
                try QueryValueAccounting.check(next, limits.maximumCollectionElements, "collectionElements")
                try planned(next, plannedColumns, "queryPlannedColumnCapacity")
                let start = columns.count
                var names: UInt64 = 0
                for index in 0..<input.count {
                    let column = input[index]
                    guard UInt64(column.number) == UInt64(index) + 1 else { throw .invalidColumnNumber(column.number) }
                    names = try QueryValueAccounting.add(names, UInt64(column.name.utf8.count))
                }
                let prospective = try QueryValueAccounting.add(utf8Bytes, names)
                try QueryValueAccounting.check(prospective, limits.maximumRetainedBytes, "retainedBytes")
                try admitStorage(nodes: records.count, columns: QueryValueAccounting.integer(next), utf8: prospective)
                columns.reserveCapacity(try QueryValueAccounting.integer(next))
                for index in 0..<input.count {
                    let column = input[index]
                    columns.append(.init(number: column.number, name: column.name, type: -1, isNullable: column.isNullable))
                }
                utf8Bytes = prospective
                let range = start..<columns.count
                work.append(.finishComposite(range))
                if !range.isEmpty { work.append(.column(input, range, 0)) }
            case .column(let input, let range, let index):
                work.append(.storeColumn(input, range, index))
                work.append(.type(input[index].type))
            case .storeColumn(let input, let range, let index):
                guard let type = results.popLast() else { throw .invalidValueConstruction }
                columns[range.lowerBound + index].type = type
                if index + 1 < range.count { work.append(.column(input, range, index + 1)) }
            case .cacheComposite(let source):
                guard let result = results.last else { throw .invalidValueConstruction }
                origins.append(.init(owner: source.storage, index: source.index, destination: result))
            case .finishArray:
                guard let child = results.popLast() else { throw .invalidValueConstruction }
                let source = records[child].logical
                results.append(try appendRecord(.array(child), logical: QueryValueFootprint(
                    nodeCount: QueryValueAccounting.add(source.nodeCount, 1),
                    collectionElementCount: QueryValueAccounting.add(source.collectionElementCount, 1),
                    retainedByteCount: 0, maximumNestingDepth: QueryValueAccounting.add(source.maximumNestingDepth, 1))))
            case .finishComposite(let range):
                var nodes: UInt64 = 1; var edges = UInt64(range.count); var depth: UInt64 = 1
                for index in range {
                    let child = records[columns[index].type].logical
                    nodes = try QueryValueAccounting.add(nodes, QueryValueAccounting.add(child.nodeCount, 1))
                    edges = try QueryValueAccounting.add(edges, child.collectionElementCount)
                    depth = max(depth, try QueryValueAccounting.add(child.maximumNestingDepth, 2))
                }
                results.append(try appendRecord(.composite(range), logical: QueryValueFootprint(nodeCount: nodes,
                    collectionElementCount: edges, retainedByteCount: 0, maximumNestingDepth: depth)))
            }
            try checkStorage()
            let scratch = try QueryValueAccounting.add(
                QueryValueAccounting.slots(work.capacity, stride: MemoryLayout<Step>.stride),
                QueryValueAccounting.slots(results.capacity, stride: MemoryLayout<Int>.stride))
            scratchByteHighWater = max(scratchByteHighWater,
                try QueryValueAccounting.add(scratch, QueryValueAccounting.add(
                    QueryValueAccounting.slots(origins.capacity, stride: MemoryLayout<Origin>.stride),
                    UInt64(MemoryLayout<[Step]>.stride + MemoryLayout<[Int]>.stride + MemoryLayout<[Origin]>.stride))))
        }
        guard results.count == 1, let result = results.first else { throw .invalidValueConstruction }
        return result
    }

    private var scalarLogical: QueryValueFootprint {
        QueryValueFootprint(nodeCount: 1, collectionElementCount: 0, retainedByteCount: 0, maximumNestingDepth: 1)
    }

    private mutating func appendRecord(_ kind: QueryTypeStorage.Kind, logical: QueryValueFootprint)
        throws(QueryValueError) -> Int {
        let count = try QueryValueAccounting.add(UInt64(records.count), 1)
        try planned(count, plannedNodes, "queryPlannedTypeNodeCapacity")
        try logical.validate(limits: limits)
        try QueryValueAccounting.check(count, limits.maximumTotalNodes, "nodes")
        try admitStorage(nodes: QueryValueAccounting.integer(count), columns: columns.count, utf8: utf8Bytes)
        let index = records.count
        records.append(.init(kind: kind, logical: logical))
        return index
    }

    private func planned(_ count: UInt64, _ ceiling: Int?, _ resource: String) throws(QueryValueError) {
        if let ceiling { try QueryValueAccounting.check(count, UInt64(ceiling), resource) }
    }

    private func admitStorage(nodes: Int, columns: Int, utf8: UInt64) throws(QueryValueError) {
        try QueryValueAccounting.check(QueryValueAccounting.add(Self.storageBytes(nodes: nodes, columns: columns), utf8),
                                       limits.maximumRetainedBytes, "retainedBytes")
    }

    private func checkStorage() throws(QueryValueError) {
        try admitStorage(nodes: records.capacity, columns: columns.capacity, utf8: utf8Bytes)
    }

    consuming func finish() throws(QueryValueError) -> QueryTypeStorage {
        try checkStorage()
        return QueryTypeStorage(records: records, columns: columns, footprint: try footprint)
    }

    private static func scalar(_ type: DataType) throws(QueryValueError) -> QueryTypeStorage.Kind {
        switch type {
        case .boolean: return .boolean
        case .smallint: return .smallint
        case .integer: return .integer
        case .bigint: return .bigint
        case .real: return .real
        case .doublePrecision: return .doublePrecision
        case .decimal(let precision, let scale): return .decimal(precision: precision, scale: scale)
        case .char(let length): return .char(length: length)
        case .varchar(let length): return .varchar(length: length)
        case .text: return .text
        case .date: return .date
        case .time(let withTimeZone, let precision): return .time(withTimeZone: withTimeZone, precision: precision)
        case .timestamp(let withTimeZone, let precision): return .timestamp(withTimeZone: withTimeZone, precision: precision)
        case .interval(let fields, let precision): return .interval(fields: fields, precision: precision)
        case .binary(let length): return .binary(length: length)
        case .varbinary(let length): return .varbinary(length: length)
        case .blob: return .blob
        case .json: return .json
        case .jsonb: return .jsonb
        case .uuid: return .uuid

        case .array, .composite, .custom: throw .incompatibleType
        }
    }
}
