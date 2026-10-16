/// The legal restricted SQL interval field ranges. An absent range means all fields.
public enum SQLIntervalFields: String, Sendable, Equatable, Hashable, CaseIterable {
    case year, month, day, hour, minute, second
    case yearToMonth, dayToHour, dayToMinute, dayToSecond
    case hourToMinute, hourToSecond, minuteToSecond
}
