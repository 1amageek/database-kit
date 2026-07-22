import DatabaseValue

public enum DatabaseReferenceError: Error, Sendable, Equatable {
    case entityMismatch(expected: String, actual: String)
    case invalidIdentifier(
        entity: String,
        reason: RecordIdentifierValidationError
    )
    case invalidPartitionFieldNumber(entity: String, field: String)
    case duplicatePartitionFieldNumber(entity: String, number: UInt32)
    case duplicatePartitionFieldName(entity: String, field: String)
}
