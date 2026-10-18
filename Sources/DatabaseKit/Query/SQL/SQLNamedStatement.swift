/// One named statement definition and its SELECT-specific metadata.
public struct SQLNamedStatement: Sendable, Equatable, Hashable {
    public let name: String
    public let columns: [String]?
    public let statement: QueryStatement
    public let materialized: Materialization?
    public let search: CTESearchClause?
    public let cycle: CTECycleClause?

    public init(name: String, columns: [String]? = nil, statement: QueryStatement,
                materialized: Materialization? = nil, search: CTESearchClause? = nil,
                cycle: CTECycleClause? = nil) {
        self.name = name
        self.columns = columns
        self.statement = statement
        self.materialized = materialized
        self.search = search
        self.cycle = cycle
    }
}

extension SQLNamedStatement {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.namedStatementMetadataEqual(lhs, rhs) && lhs.statement == rhs.statement
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hashNamedStatementMetadata(self, into: &hasher)
        hasher.combine(statement)
    }
}
