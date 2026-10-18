/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLViewColumnBinding: Sendable, Hashable {
    public let id: String
    public let name: String
    public let type: QueryColumnType

    public init(id: String, name: String, type: QueryColumnType) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else { throw .invalidViewDefinition }
        self.type = type
        self.id = id
        self.name = name
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(type)
    }
}
