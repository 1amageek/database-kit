import DatabaseTypes

public enum PersistableReferenceError: Error, Sendable, Equatable {
    case entityMismatch(expected: String, actual: String)
    case invalidIdentifier(
        entity: String,
        reason: PersistableIdentifierValidationError
    )
    case partitionMismatch(
        entity: String,
        expected: [String],
        actual: [String]
    )
}

extension PersistableReferenceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .entityMismatch(let expected, let actual):
            return "expected entity '\(expected)', received '\(actual)'"
        case .invalidIdentifier(let entity, let reason):
            return "entity '\(entity)' has invalid identifier: \(reason)"
        case .partitionMismatch(let entity, let expected, let actual):
            return "entity '\(entity)' expected partitions \(expected), received \(actual)"
        }
    }
}
