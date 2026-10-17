/// Ordered SQL grouping structure, including composite keys and empty grouping sets.
public indirect enum GroupingElement: Sendable, Hashable {
    case expression(Expression)
    case rollup([[Expression]])
    case cube([[Expression]])
    case groupingSets([[GroupingElement]])

    public static func == (lhs: Self, rhs: Self) -> Bool { ExpressionIdentity.areEqual(lhs, rhs) }
    public func hash(into hasher: inout Hasher) { ExpressionIdentity.hash(self, into: &hasher) }
}
