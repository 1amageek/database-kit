/// A failure in a declarative index contract.
public enum IndexValidationError:
    Error,
    Sendable,
    Equatable,
    CustomStringConvertible
{
    case unsupportedField(
        index: String,
        field: FieldSchema,
        reason: String
    )
    case invalidFieldCount(index: String, expected: Int, actual: Int)
    case invalidConfiguration(index: String, reason: String)

    public var description: String {
        switch self {
        case let .unsupportedField(index, field, reason):
            return "Index '\(index)' does not support field '\(field.name)' of type '\(field.type.rawValue)': \(reason)"
        case let .invalidFieldCount(index, expected, actual):
            return "Index '\(index)' expects \(expected) field(s), but got \(actual)"
        case let .invalidConfiguration(index, reason):
            return "Index '\(index)' has invalid configuration: \(reason)"
        }
    }
}
