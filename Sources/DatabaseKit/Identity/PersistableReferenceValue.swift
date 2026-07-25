import DatabaseTypes

/// A typed model value that stores a canonical persistable identity.
public protocol PersistableReferenceValue: FieldValueEncodable {
    var persistableIdentity: EntityReference { get }

    static func decodePersistedReference(
        _ identity: EntityReference
    ) throws -> Self
}

public extension PersistableReferenceValue {
    static var fieldSchemaType: FieldSchemaType { .reference }

    func encodeFieldValue() -> FieldValue {
        .reference(persistableIdentity)
    }
}
