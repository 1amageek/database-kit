public struct QueryCompositeType: Sendable, Hashable {
    let storage: QueryTypeStorage
    let index: Int

    init(storage: QueryTypeStorage, index: Int) {
        self.storage = storage
        self.index = index
    }

    public init(columns: [QueryColumn], limits: QueryValueLimits) throws(QueryValueError) {
        var builder = QueryTypeBuilder(limits: limits)
        let root = try builder.append(columns: .owned(columns))
        self.init(storage: try builder.finish(), index: root)
    }

    public init(columns: [QueryColumn], limits: QueryValueLimits,
                typeNodeCapacity: Int, columnCapacity: Int) throws(QueryValueError) {
        var builder = try QueryTypeBuilder(limits: limits,
            typeNodeCapacity: typeNodeCapacity, columnCapacity: columnCapacity)
        let root = try builder.append(columns: .owned(columns))
        self.init(storage: try builder.finish(), index: root)
    }

    public var columns: QueryCompositeColumns {
        guard case .composite(let range) = storage.records[index].kind else {
            preconditionFailure("A composite descriptor requires a composite record")
        }
        return QueryCompositeColumns(storage: storage, range: range)
    }

    public var storageFootprint: QueryTypeStorageFootprint { storage.footprint }

    public func measure() throws(QueryValueError) -> QueryValueFootprint {
        let logical = storage.records[index].logical
        return QueryValueFootprint(nodeCount: logical.nodeCount,
            collectionElementCount: logical.collectionElementCount,
            retainedByteCount: try QueryValueAccounting.add(storage.footprint.retainedStorageByteCount,
                                                            storage.footprint.utf8ByteCount),
            maximumNestingDepth: logical.maximumNestingDepth)
    }

    public static func constructionByteCount(typeNodeCapacity: Int, columnCapacity: Int)
        throws(QueryValueError) -> UInt64 {
        try QueryTypeBuilder.constructionByteCount(typeNodeCapacity: typeNodeCapacity,
                                                        columnCapacity: columnCapacity)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        QueryTypeStorage.areEqual(lhs.storage, lhs.index, rhs.storage, rhs.index)
    }

    public func hash(into hasher: inout Hasher) { storage.hash(index, into: &hasher) }
}
