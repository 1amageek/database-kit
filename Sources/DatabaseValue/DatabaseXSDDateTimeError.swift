public enum DatabaseXSDDateTimeError: Error, Sendable, Equatable {
    case invalidDate(DatabaseDate)
    case invalidNanoseconds(UInt32)
    case timestampOutOfSupportedYearRange
}
