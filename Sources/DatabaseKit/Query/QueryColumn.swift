public struct QueryColumn: Sendable, Hashable {
    public let number: UInt32
    public let name: String
    public let type: QueryColumnType
    public let isNullable: Bool

    public init(number: UInt32, name: String, type: QueryColumnType,
                isNullable: Bool) throws(QueryValueError) {
        guard number > 0 else { throw .invalidColumnNumber(number) }
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else {
            throw .incompatibleType
        }
        self.number = number
        self.name = name
        self.type = type
        self.isNullable = isNullable
    }

    public static func validate(_ columns: [Self]) throws(QueryValueError) {
        for (index, column) in columns.enumerated() {
            guard UInt64(column.number) == UInt64(index) + 1 else {
                throw .invalidColumnNumber(column.number)
            }
        }
    }

    init(validatedNumber: UInt32, name: String, type: QueryColumnType, isNullable: Bool) {
        self.number = validatedNumber
        self.name = name
        self.type = type
        self.isNullable = isNullable
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.number == rhs.number && lhs.name.utf8.elementsEqual(rhs.name.utf8)
            && lhs.type == rhs.type && lhs.isNullable == rhs.isNullable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(number)
        hasher.combine(name.utf8.count)
        for byte in name.utf8 { hasher.combine(byte) }
        hasher.combine(type)
        hasher.combine(isNullable)
    }
}
