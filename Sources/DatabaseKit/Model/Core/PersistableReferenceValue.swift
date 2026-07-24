import DatabaseTypes

/// A typed model value that stores a canonical persistable identity.
public protocol PersistableReferenceValue: Codable, Sendable {
    var persistableIdentity: EntityReference { get }

    static func decodePersistedReference(
        _ identity: EntityReference
    ) throws -> Self
}
