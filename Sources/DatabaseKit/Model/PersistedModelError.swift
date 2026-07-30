public enum PersistedModelError: Error, Sendable, Equatable {
    case emptyEntity
    case entityMismatch(expected: String, actual: String)
    case duplicateFieldName(String)
    case duplicateFieldNumber(UInt32)
}
