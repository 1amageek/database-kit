import DatabaseTypes

public enum DatabaseReferenceError: Error, Sendable, Equatable {
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
