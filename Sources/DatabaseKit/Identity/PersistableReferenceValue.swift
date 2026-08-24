import DatabaseTypes

/// A typed model value that stores a canonical persistable identity.
public protocol PersistableReferenceValue:
    FieldValueEncodable,
    FieldValueRepresentable
{
    var persistableIdentity: EntityReference { get }

    static func decodePersistedReference(
        _ identity: EntityReference
    ) throws(PersistableReferenceError) -> Self
}

public extension PersistableReferenceValue {
    static var fieldSchemaType: FieldSchemaType { .reference }

    var fieldValue: FieldValue {
        .reference(persistableIdentity)
    }

    func encodeFieldValue() -> FieldValue { fieldValue }
}
