/// A scalar comparison selected by a quantified SQL predicate.
public enum ComparisonOperator: Sendable, Equatable, Hashable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
}
