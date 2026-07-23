public enum PersistableIdentifierValidationError: Error, Sendable, Equatable {
    case typeMismatch(expected: PersistableIdentifierType)
    case emptyComposite
    case compositeDepthExceeded(actual: Int, maximum: Int)
    case componentCountExceeded(actual: Int, maximum: Int)
}
