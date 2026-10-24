/// The source representation of one request; execution always consumes the IR.
public enum QueryInput: Sendable, Hashable {
    case text(language: QueryLanguage, statement: String)
    case statement(QueryStatement)
    case block(SQLBlock)

    public static func sql(_ source: String) -> Self {
        .text(language: .sql, statement: source)
    }
}
