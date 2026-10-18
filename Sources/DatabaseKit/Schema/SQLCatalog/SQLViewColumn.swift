/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLViewColumn: Sendable, Hashable {
    public let id: String
    public let name: String
    public let type: QueryColumnType
    public let isNullable: Bool

    public init(id: String, name: String, type: QueryColumnType, isNullable: Bool) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else { throw .invalidViewDefinition }
        self.id = id
        self.name = name
        self.type = type
        self.isNullable = isNullable
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.type == rhs.type
            && lhs.isNullable == rhs.isNullable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(type)
        hasher.combine(isNullable)
    }
}
