public enum QueryLiteralConversionError: Error, Sendable, Equatable {
    /// The value belongs to the database value model but has no QueryIR literal representation.
    case unsupportedFieldValue

    /// The exact decimal value exceeds the coefficient or scale supported by QueryIR.
    case decimalOutOfRange

    /// A decimal does not represent a finite numeric value.
    case nonFiniteDecimal

    /// A timestamp is not finite.
    case nonFiniteTimestamp

    /// A timestamp exceeds the seconds range supported by QueryIR.
    case timestampOutOfRange
}

extension QueryLiteralConversionError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unsupportedFieldValue:
            return "The database value cannot be represented as a QueryIR literal"
        case .decimalOutOfRange:
            return "The exact decimal value exceeds the QueryIR decimal range"
        case .nonFiniteDecimal:
            return "A non-finite decimal cannot be represented as a QueryIR literal"
        case .nonFiniteTimestamp:
            return "A non-finite timestamp cannot be represented as a QueryIR literal"
        case .timestampOutOfRange:
            return "The timestamp exceeds the QueryIR timestamp range"
        }
    }
}
