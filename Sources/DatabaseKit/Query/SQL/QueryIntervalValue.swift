import DatabaseTypes

public struct QueryIntervalValue: Sendable, Hashable {
    public let period: CalendarPeriod
    public let time: TimeSpan
    public let microseconds: Int64

    public init(period: CalendarPeriod, time: TimeSpan) throws(QueryValueError) {
        guard Int32(exactly: period.months) != nil, Int32(exactly: period.days) != nil,
              time.nanoseconds.isMultiple(of: 1000) else { throw .intervalOutOfRange }
        let micros = Int128(time.seconds) * 1_000_000 + Int128(time.nanoseconds / 1000)
        guard let microseconds = Int64(exactly: micros) else { throw .intervalOutOfRange }
        self.period = period
        self.time = time
        self.microseconds = microseconds
    }
}
