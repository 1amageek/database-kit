import DatabaseValue

/// A typed model value that stores a canonical persistable identity.
public protocol PersistableReferenceValue: Codable, Sendable {
    var persistableIdentity: PersistableIdentity { get }

    static func decodePersistedReference(
        _ identity: PersistableIdentity
    ) throws -> Self
}
