import DatabaseKit
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

extension Foundation.UUID: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uuid }

    public func encodeFieldValue() -> FieldValue {
        .uuid(DatabaseTypes.UUID(self))
    }
}

extension Foundation.UUID: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Foundation.UUID {
        guard case .uuid(let uuid) = value else {
            throw .invalidValue(
                field: field,
                expected: "a UUID"
            )
        }
        return Foundation.UUID(uuid)
    }
}

extension Foundation.UUID: PersistableIdentifier {
    public static var persistableIdentifierType: PersistableIdentifierType {
        .uuid
    }

    public var persistableIdentifierValue: ReferenceIdentifier {
        .uuid(DatabaseTypes.UUID(self))
    }
}
