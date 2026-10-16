/// One SQL array dimension: a scalar index or a slice with optional bounds.
public enum ArraySubscript: Sendable, Hashable {
    case index(Expression)
    case slice(lower: Expression?, upper: Expression?)
}
