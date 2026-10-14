public struct QueryArray<Element: QueryArrayElement>: Sendable {
    public let dimensions: [QueryArrayDimension]
    public let elements: [Element?]
    public let arrayValue: QueryArrayValue

    public init(dimensions: [QueryArrayDimension], elements: [Element?],
                limits: QueryValueLimits) throws(QueryValueError) {
        guard UInt64(elements.count) <= limits.maximumCollectionElements else {
            throw .resourceLimit(resource: "collectionElements", actual: UInt64(elements.count),
                                 maximum: limits.maximumCollectionElements)
        }
        var values: [QueryValue] = []
        values.reserveCapacity(elements.count)
        for element in elements {
            if let element { values.append(try element.queryValue) }
            else { values.append(.primitive(.null)) }
        }
        let value = try QueryArrayValue(elementType: Element.queryDataType,
                                        dimensions: dimensions, elements: values, limits: limits)
        self.dimensions = dimensions
        self.elements = elements
        self.arrayValue = value
    }

    public init(arrayValue: QueryArrayValue, limits: QueryValueLimits) throws(QueryValueError) {
        guard arrayValue.elementType == Element.queryDataType else { throw .incompatibleType }
        try QueryValueValidator.validate(.array(arrayValue), limits: limits)
        var elements: [Element?] = []
        elements.reserveCapacity(arrayValue.elements.count)
        for value in arrayValue.elements {
            elements.append(value.isNull ? nil : try Element.decodeQueryValue(value))
        }
        self.dimensions = arrayValue.dimensions
        self.elements = elements
        self.arrayValue = arrayValue
    }
}

extension QueryArray: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.arrayValue == rhs.arrayValue }
}

extension QueryArray: Hashable where Element: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(arrayValue) }
}
