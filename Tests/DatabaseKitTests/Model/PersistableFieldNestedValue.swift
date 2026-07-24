import DatabaseTypes
import DatabaseKit

struct PersistableFieldNestedValue:
    Sendable,
    Equatable,
    FieldValueConvertible,
    FieldValueDecodable
{
    let label: String
    let priority: Int64

    func toFieldValue() -> FieldValue {
        .object(
            try! FieldObject([
                (key: "label", value: .string(label)),
                (key: "priority", value: .int64(priority)),
            ])
        )
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
