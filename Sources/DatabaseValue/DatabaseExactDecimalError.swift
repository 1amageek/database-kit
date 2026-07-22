public enum DatabaseExactDecimalError: Error, Sendable, Equatable {
    case numericOverflow
    case divisionByZero
    case inexactResult
}
