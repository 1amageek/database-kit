public enum RecordIdentifierValidationError: Error, Sendable, Equatable {
    case typeMismatch(expected: RecordIdentifierType)
    case emptyComposite
    case compositeDepthExceeded(actual: Int, maximum: Int)
    case componentCountExceeded(actual: Int, maximum: Int)
}
