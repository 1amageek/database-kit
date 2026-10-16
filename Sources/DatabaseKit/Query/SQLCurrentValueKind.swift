/// SQL current-value forms whose value is supplied by the execution environment.
public enum SQLCurrentValueKind: String, Sendable, Equatable, Hashable, CaseIterable {
    case date, time, timestamp, localTime, localTimestamp
}
