/// Stable identity of one persisted index within a schema.
public struct IndexIdentity: Sendable, Hashable, Comparable {
    public let entityName: String
    public let name: String

    public init(entityName: String, name: String) {
        self.entityName = entityName
        self.name = name
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.entityName != rhs.entityName {
            return lhs.entityName < rhs.entityName
        }
        return lhs.name < rhs.name
    }
}

/// Stable identity of one logical index shared by a polymorphic group.
public struct PolymorphicIndexIdentity: Sendable, Hashable, Comparable {
    public let groupIdentifier: String
    public let name: String

    public init(groupIdentifier: String, name: String) {
        self.groupIdentifier = groupIdentifier
        self.name = name
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.groupIdentifier != rhs.groupIdentifier {
            return lhs.groupIdentifier < rhs.groupIdentifier
        }
        return lhs.name < rhs.name
    }
}
