/// The declared candidate source of a scalar quantified comparison.
public enum QuantifiedComparisonSource: Sendable, Equatable, Hashable {
    case array(Expression)
    case subquery(SelectQuery)
}
