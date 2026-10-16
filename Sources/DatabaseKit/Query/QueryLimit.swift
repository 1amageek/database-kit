public enum QueryLimit: Sendable, Hashable {
    case all
    case count(QueryCount, withTies: Bool)
}
