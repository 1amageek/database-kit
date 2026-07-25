/// Time window represented by a leaderboard index.
public enum LeaderboardWindowType: Sendable, Hashable {
    case hourly
    case daily
    case weekly
    case monthly
    case custom(duration: Double)

    /// Duration represented by one window, in seconds.
    public var durationSeconds: Double {
        switch self {
        case .hourly:
            3_600
        case .daily:
            86_400
        case .weekly:
            604_800
        case .monthly:
            2_592_000
        case .custom(let duration):
            duration
        }
    }
}
