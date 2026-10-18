/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLMaterializedView: Sendable, Hashable {
    public let id: String
    public let namespaceID: String
    public let name: String
    public let definition: SQLViewDefinition
    public let backingRelationID: String
    public let isPopulated: Bool

    public init(id: String, namespaceID: String, name: String, definition: SQLViewDefinition, backingRelationID: String, isPopulated: Bool) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        try SQLIdentifier.validate(backingRelationID)
        self.id = id
        self.namespaceID = namespaceID
        self.name = name
        self.definition = definition
        self.backingRelationID = backingRelationID
        self.isPopulated = isPopulated
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.namespaceID) == SQLIdentifier(value: rhs.namespaceID)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.definition == rhs.definition
            && SQLIdentifier(value: lhs.backingRelationID) == SQLIdentifier(value: rhs.backingRelationID)
            && lhs.isPopulated == rhs.isPopulated
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: namespaceID))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(definition)
        hasher.combine(SQLIdentifier(value: backingRelationID))
        hasher.combine(isPopulated)
    }
}
