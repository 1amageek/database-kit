/// A SQL wall-clock time and its explicit offset, measured east of UTC.
public struct QueryTimeWithTimeZoneValue: Sendable, Hashable {
    public let time: QueryTimeValue
    public let utcOffsetSeconds: Int32

    /// Runtime zone operations can produce offsets beyond lexical input bounds.
    public init(time: QueryTimeValue, utcOffsetSeconds: Int32) {
        self.time = time
        self.utcOffsetSeconds = utcOffsetSeconds
    }
}
