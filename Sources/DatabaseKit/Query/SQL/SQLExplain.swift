/// Inspects an ordinary statement through its actual execution owner.
public struct SQLExplain: Sendable, Hashable {
    public let statement: QueryStatement
    public let options: SQLExplainOptions
    public init(statement: QueryStatement, options: SQLExplainOptions = .init()) {
        self.statement = statement; self.options = options
    }
}
