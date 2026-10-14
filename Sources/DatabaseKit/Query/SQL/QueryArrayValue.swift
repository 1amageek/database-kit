public struct QueryArrayValue: Sendable, Hashable {
    public let elementType: DataType
    public let dimensions: [QueryArrayDimension]
    public let elements: [QueryValue]

    public init(elementType: DataType, dimensions: [QueryArrayDimension],
                elements: [QueryValue], limits: QueryValueLimits) throws(QueryValueError) {
        try Self.validateShapeAndTypes(elementType: elementType, dimensions: dimensions, elements: elements)
        self.elementType = elementType
        self.dimensions = dimensions
        self.elements = elements
        try QueryValueValidator.validate(.array(self), type: .sql(.array(elementType)), limits: limits)
    }

    /// Used only by the codec after one root's retention and child ledgers are admitted.
    /// It preserves intrinsic validation without recharging aliased root capacities.
    package init(admittedElementType elementType: DataType, dimensions: [QueryArrayDimension],
                 elements: [QueryValue]) throws(QueryValueError) {
        try Self.validateShapeAndTypes(elementType: elementType, dimensions: dimensions, elements: elements)
        self.elementType = elementType
        self.dimensions = dimensions
        self.elements = elements
    }

    private static func validateShapeAndTypes(elementType: DataType, dimensions: [QueryArrayDimension],
                                              elements: [QueryValue]) throws(QueryValueError) {
        guard dimensions.count <= 6 else { throw .invalidDimensionCount(dimensions.count) }
        if case .array = elementType { throw .incompatibleType }
        guard QueryValueValidator.accepts(.primitive(.null), type: .sql(elementType)) else {
            throw .incompatibleType
        }
        var product: UInt64 = dimensions.isEmpty ? 0 : 1
        for dimension in dimensions {
            let next = product.multipliedReportingOverflow(by: UInt64(dimension.length))
            guard !next.overflow else { throw .dimensionProductOverflow }
            product = next.partialValue
        }
        guard product == UInt64(elements.count) else {
            throw .elementCountMismatch(expected: product, actual: UInt64(elements.count))
        }
        for (index, element) in elements.enumerated() {
            guard QueryValueValidator.accepts(element, type: .sql(elementType)) else {
                throw .elementTypeMismatch(index: UInt64(index))
            }
        }
    }
}
