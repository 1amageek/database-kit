/// A MERGE statement preserving candidate match classes and clause order.
public struct MergeQuery: Sendable, Equatable, Hashable {
    public let target: TableRef
    public let source: DataSource
    public let condition: Expression
    public let clauses: [SQLMergeClause]
    public let returning: [ProjectionItem]?
    public let returningAliases: SQLReturningAliases?

    public init(target: TableRef, source: DataSource, condition: Expression,
                clauses: [SQLMergeClause], returning: [ProjectionItem]? = nil,
                returningAliases: SQLReturningAliases? = nil) {
        self.target = target
        self.source = source
        self.condition = condition
        self.clauses = clauses
        self.returning = returning
        self.returningAliases = returningAliases
    }
}
