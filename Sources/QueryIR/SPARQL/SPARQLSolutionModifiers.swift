/// SPARQL solution modifiers in specification evaluation order.
public struct SPARQLSolutionModifiers: Sendable, Equatable, Hashable {
    public let groupBy: [Expression]
    public let having: [Expression]
    public let orderBy: [SortKey]
    public let limit: Int?
    public let offset: Int?

    public init(
        groupBy: [Expression] = [],
        having: [Expression] = [],
        orderBy: [SortKey] = [],
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.groupBy = groupBy
        self.having = having
        self.orderBy = orderBy
        self.limit = limit
        self.offset = offset
    }

    public static let none = SPARQLSolutionModifiers()

    /// HAVING conditions are conjunctive in SPARQL algebra.
    public var combinedHaving: Expression? {
        guard !having.isEmpty else { return nil }
        return combineHaving(in: having.indices)
    }

    /// Builds a balanced conjunction so wire-decoder and evaluator recursion
    /// depth grows logarithmically with the number of HAVING conditions.
    private func combineHaving(in range: Range<Int>) -> Expression {
        precondition(!range.isEmpty)
        if range.count == 1 {
            return having[range.lowerBound]
        }
        let midpoint = range.lowerBound + range.count / 2
        return .and(
            combineHaving(in: range.lowerBound..<midpoint),
            combineHaving(in: midpoint..<range.upperBound)
        )
    }
}
