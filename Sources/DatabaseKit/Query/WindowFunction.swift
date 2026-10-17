/// SQL window WindowFunction declaration.
public enum WindowFunction: Sendable, Hashable {
    case aggregate(SQLAggregateCall)
    case analytic(SQLWindowFunction, arguments: [Expression])
}
