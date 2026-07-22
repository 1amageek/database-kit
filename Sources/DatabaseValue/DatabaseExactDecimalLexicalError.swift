public enum DatabaseExactDecimalLexicalError: Error, Sendable, Equatable {
    case invalidMaximumUTF8Count(Int)
    case representationTooLarge(required: UInt64, maximum: UInt64)
}
