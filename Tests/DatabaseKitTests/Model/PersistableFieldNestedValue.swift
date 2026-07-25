import DatabaseTypes
import DatabaseKit

struct PersistableFieldNestedValue:
    Sendable,
    Equatable,
    FieldValueEncodable,
    FieldValueDecodable
{
    let label: String
    let priority: Int64

    static var fieldSchemaType: FieldSchemaType { .nested }

    func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        do {
            return .object(
                try FieldObject([
                (key: "label", value: .string(label)),
                (key: "priority", value: .int64(priority)),
                ])
            )
        } catch let error {
            switch error {
            case .duplicateKey(let name):
                throw .invalidSchema(
                    entity: "PersistableFieldNestedValue",
                    reason: "field '\(name)' is declared more than once"
                )
            }
        }
    }

    static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> PersistableFieldNestedValue {
        guard case .object(let object) = value,
              case .string(let label) = object["label"],
              case .int64(let priority) = object["priority"] else {
            throw PersistableDecodingError.invalidValue(
                field: field,
                expected: "a nested value object"
            )
        }
        return PersistableFieldNestedValue(label: label, priority: priority)
    }
}
