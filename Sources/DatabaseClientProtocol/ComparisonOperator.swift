/// Comparison operators for field-level predicates
///
/// Used in both client-side query building and server-side evaluation.
/// String raw values enable stable serialization across protocol versions.
public enum ComparisonOperator: String, Sendable, Codable, Hashable {
    case equal = "=="
    case notEqual = "!="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case contains = "contains"
    case hasPrefix = "hasPrefix"
    case hasSuffix = "hasSuffix"
    case `in` = "in"
    case isNil = "isNil"
    case isNotNil = "isNotNil"
}
