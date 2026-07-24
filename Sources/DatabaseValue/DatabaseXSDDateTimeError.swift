import DatabaseTypes

public enum XSDDateTimeError: Error, Sendable, Equatable {
    case timestampOutOfSupportedYearRange
}
