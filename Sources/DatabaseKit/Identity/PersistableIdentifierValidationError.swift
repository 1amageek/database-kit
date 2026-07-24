import DatabaseTypes

public enum PersistableIdentifierValidationError:
    Error,
    Sendable,
    Equatable {
    case invalidValue(ReferenceIdentifierValidationError)
    case typeMismatch(
        expected: PersistableIdentifierType,
        actual: PersistableIdentifierType
    )
    case componentCountMismatch(expected: Int, actual: Int)
}
