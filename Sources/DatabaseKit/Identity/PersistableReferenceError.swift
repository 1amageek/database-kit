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
