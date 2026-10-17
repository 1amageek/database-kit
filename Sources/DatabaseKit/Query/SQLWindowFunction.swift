/// Closed SQL function identity; runtime signatures belong to the SQL binder.
public enum SQLWindowFunction: String, Sendable, Hashable, CaseIterable {
    case rowNumber = "row_number"
    case rank
    case denseRank = "dense_rank"
    case percentRank = "percent_rank"
    case cumeDist = "cume_dist"
    case ntile
    case lag
    case lead
    case firstValue = "first_value"
    case lastValue = "last_value"
    case nthValue = "nth_value"
}
