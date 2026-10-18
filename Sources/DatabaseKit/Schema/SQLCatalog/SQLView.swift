/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLView: Sendable, Hashable {
    public let id: String
    public let namespaceID: String
    public let name: String
    public let definition: SQLViewDefinition

    public init(id: String, namespaceID: String, name: String, definition: SQLViewDefinition) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        self.id = id
        self.namespaceID = namespaceID
        self.name = name
        self.definition = definition
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.namespaceID) == SQLIdentifier(value: rhs.namespaceID)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.definition == rhs.definition
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: namespaceID))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(definition)
    }
}
