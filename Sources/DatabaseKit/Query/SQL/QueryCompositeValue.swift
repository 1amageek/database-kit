public struct QueryCompositeValue: Sendable, Hashable {
    let storage: QueryValueStorage
    let index: Int

    init(storage: QueryValueStorage, index: Int) {
        self.storage = storage
        self.index = index
    }

    public init(type: QueryCompositeType, fields: [QueryValue], limits: QueryValueLimits) throws(QueryValueError) {
        var builder = QueryValueBuilder(limits: limits)
        var indices: [Int] = []
        try QueryValueAccounting.check(UInt64(fields.count), limits.maximumCollectionElements, "collectionElements")
        indices.reserveCapacity(fields.count)
        for field in fields { indices.append(try builder.append(field)) }
        let root = try builder.appendComposite(type: type, fields: indices)
        guard case .composite(let value) = try builder.finish(root: root) else { throw .invalidValueConstruction }
        self = value
    }

    public var type: QueryCompositeType {
        guard case .composite(let type, _) = storage.records[index].kind else {
            preconditionFailure("A composite value requires a composite record")
        }
        return QueryCompositeType(storage: storage.types, index: type)
    }

    public var fields: QueryValueElements {
        guard case .composite(_, let range) = storage.records[index].kind else {
            preconditionFailure("A composite value requires a composite record")
        }
        return QueryValueElements(storage: storage, range: range)
    }

    public var storageFootprint: QueryValueStorageFootprint { storage.footprint }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        QueryValueIdentity.areEqual(.composite(lhs), .composite(rhs))
    }

    public func hash(into hasher: inout Hasher) { QueryValueIdentity.hash(.composite(self), into: &hasher) }
}
