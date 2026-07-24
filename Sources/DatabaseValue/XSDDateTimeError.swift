import DatabaseTypes

/// A failure to represent a timestamp in the supported XSD dateTime domain.
public enum XSDDateTimeError: Error, Sendable, Equatable {
    case timestampOutOfSupportedYearRange
}
