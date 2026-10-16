/// A fixed unsigned count or an SQL expression resolved at invocation.
public enum QueryCount: Sendable, Hashable {
    case fixed(UInt64)
    case expression(Expression)
}
