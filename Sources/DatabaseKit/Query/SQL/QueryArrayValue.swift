public struct QueryArrayValue: Sendable, Hashable {
    let storage: QueryValueStorage
    let index: Int

    init(storage: QueryValueStorage, index: Int) { self.storage = storage; self.index = index }

    public var elementType: DataType {
        guard case .array(let type, _, _) = storage.records[index].kind,
              case .sql(let sql) = storage.types.type(at: type) else {
            preconditionFailure("An array value requires a SQL element descriptor")
        }
        return sql
    }

    public var dimensions: QueryArrayDimensions {
        guard case .array(_, let dimensions, _) = storage.records[index].kind else {
            preconditionFailure("An array value requires array dimensions")
        }
        return QueryArrayDimensions(storage: storage, range: dimensions)
    }

    public var elements: QueryValueElements {
        guard case .array(_, _, let elements) = storage.records[index].kind else {
            preconditionFailure("An array value requires array elements")
        }
        return QueryValueElements(storage: storage, range: elements)
    }

    public var storageFootprint: QueryValueStorageFootprint { storage.footprint }

    public init(elementType: DataType, dimensions: [QueryArrayDimension],
                elements: [QueryValue], limits: QueryValueLimits) throws(QueryValueError) {
        try Self.validateShape(elementType: elementType, dimensions: dimensions, count: elements.count)
        var builder = QueryValueBuilder(limits: limits)
        var ids: [Int] = []
        try QueryValueAccounting.check(UInt64(elements.count), limits.maximumCollectionElements, "collectionElements")
        ids.reserveCapacity(elements.count)
        for element in elements { ids.append(try builder.append(element)) }
        let root = try builder.appendArray(elementType: elementType, dimensions: dimensions, elements: ids)
        guard case .array(let value) = try builder.finish(root: root) else { throw .invalidValueConstruction }
        self = value
    }

    /// The Wire root owns retention admission; this initializer never resets its ledger.
    package init(admittedElementType elementType: DataType, dimensions: [QueryArrayDimension],
                 elements: [QueryValue]) throws(QueryValueError) {
        try self.init(elementType: elementType, dimensions: dimensions, elements: elements,
            limits: QueryValueLimits(maximumRetainedBytes: .max, maximumTotalNodes: .max,
                                     maximumNestingDepth: .max, maximumCollectionElements: .max))
    }

    static func validateShape(elementType: DataType, dimensions: [QueryArrayDimension], count: Int) throws(QueryValueError) {
        guard dimensions.count <= 6 else { throw .invalidDimensionCount(dimensions.count) }
        if case .array = elementType { throw .incompatibleType }
        guard QueryValueValidator.accepts(.primitive(.null), type: .sql(elementType)) else { throw .incompatibleType }
        var product: UInt64 = dimensions.isEmpty ? 0 : 1
        for dimension in dimensions {
            let result = product.multipliedReportingOverflow(by: UInt64(dimension.length))
            guard !result.overflow else { throw .dimensionProductOverflow }
            product = result.partialValue
        }
        guard product == UInt64(count) else {
            throw .elementCountMismatch(expected: product, actual: UInt64(count))
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { QueryValueIdentity.areEqual(.array(lhs), .array(rhs)) }
    public func hash(into hasher: inout Hasher) { QueryValueIdentity.hash(.array(self), into: &hasher) }
}
