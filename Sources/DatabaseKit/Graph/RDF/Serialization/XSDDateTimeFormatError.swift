import DatabaseTypes

/// A failure to represent a timestamp in the supported XSD dateTime domain.
public enum XSDDateTimeFormatError: Error, Sendable, Equatable {
    case timestampOutOfSupportedYearRange
}
