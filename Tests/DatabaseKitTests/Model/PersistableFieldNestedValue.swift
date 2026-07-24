import DatabaseTypes
import DatabaseKit

struct PersistableFieldNestedValue:
    Sendable,
    Equatable,
    FieldValueConvertible,
    PersistableScalarDecodable
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

    static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> PersistableFieldNestedValue {
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
