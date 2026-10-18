/// One ordered MERGE branch.
public struct SQLMergeClause: Sendable, Equatable, Hashable {
    public let match: SQLMergeMatch
    public let condition: Expression?
    public let action: SQLMergeAction

    public init(match: SQLMergeMatch, condition: Expression? = nil, action: SQLMergeAction) {
        self.match = match
        self.condition = condition
        self.action = action
    }
}
