/// An immutable logical namespace, independent of storage placement and authority.
public struct SQLNamespace: Sendable, Hashable {
    public let id: String
    public let name: String

    public init(id: String, name: String) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        self.id = id
        self.name = name
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: name))
    }
}
