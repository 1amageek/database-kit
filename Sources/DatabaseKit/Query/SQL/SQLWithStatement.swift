/// A statement-level WITH whose writable definitions execute independently of demand.
public struct SQLWithStatement: Sendable, Equatable, Hashable {
    public let recursive: Bool
    public let statements: [SQLNamedStatement]
    public let body: QueryStatement

    public init(recursive: Bool = false, statements: [SQLNamedStatement], body: QueryStatement) {
        self.recursive = recursive
        self.statements = statements
        self.body = body
    }
}
