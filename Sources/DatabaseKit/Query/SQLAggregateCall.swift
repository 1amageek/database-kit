/// Immutable SQL SQLAggregateCall declaration; execution is owned by the SQL runtime.
public struct SQLAggregateCall: Sendable, Hashable {
    public let function: SQLAggregateFunction
    public let arguments: [Expression]
    public let distinct: Bool
    public let orderBy: [SortKey]
    public let filter: Expression?
    public let withinGroup: [SortKey]?
    public let schema: String?

    public init(function: SQLAggregateFunction, arguments: [Expression], distinct: Bool = false, orderBy: [SortKey] = [], filter: Expression? = nil, withinGroup: [SortKey]? = nil, schema: String? = nil) {
        self.function = function
        self.arguments = arguments
        self.distinct = distinct
        self.orderBy = orderBy
        self.filter = filter
        self.withinGroup = withinGroup
        self.schema = schema
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.areEqual(.aggregate(.sql(lhs)), .aggregate(.sql(rhs)))
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(.aggregate(.sql(self)), into: &hasher)
    }
}
