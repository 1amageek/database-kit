/// SQL write-time value generation, independent of application model defaults.
public enum SQLColumnPolicy: Sendable, Hashable {
    case input(defaultExpression: Expression?)
    case generated(Expression)
    case identity(SQLIdentityColumn)
}
