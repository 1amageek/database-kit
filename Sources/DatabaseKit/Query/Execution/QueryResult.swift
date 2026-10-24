import DatabaseTypes

/// Final statement outcomes, independent of storage, transport and retrieval.
public enum QueryResult<Rows: QueryRows, Graph: QueryGraph, Boolean: QueryBoolean>: Sendable {
    case rows(Rows)
    case boolean(Boolean)
    case rdfGraph(Graph)
    case command(SQLCommandKind, affectedRows: UInt64?)
    case copy(bytes: ByteString, affectedRows: UInt64)
    case block([Self])

    /// Non-row outcomes have no row schema; block members retain their own rows.
    public var rows: Rows {
        if case .rows(let rows) = self { return rows }
        return .empty
    }

    public var columns: [QueryColumn] { rows.columns }

    public var command: SQLCommandKind? {
        if case .command(let kind, _) = self { return kind }
        return nil
    }

    public var affectedRows: UInt64? {
        switch self {
        case .rows(let rows): rows.affectedRows
        case .command(_, let count): count
        case .copy(_, let count): count
        case .boolean, .rdfGraph, .block: nil
        }
    }

    /// Preserves block order without flattening unrelated column schemas.
    public var results: [Self] {
        if case .block(let results) = self { return results }
        return [self]
    }

    public init(results: [Self]) throws(QueryResultError) {
        guard !results.isEmpty else { throw .emptyBlock }
        for result in results {
            if case .block = result { throw .nestedBlock }
        }
        self = results.count == 1 ? results[0] : .block(results)
    }
}
