/// A canonical scalar comparison used by SQL and SPARQL predicates.
public enum ComparisonOperator: Sendable, Equatable, Hashable {
    case equal
    case notEqual
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
}
