/// A context-free source of canonical query data.
public protocol QuerySource: Sendable {
    var querySource: DataSource { get }
}

extension TableRef: QuerySource {
    public var querySource: DataSource {
        guard let alias else { return .table(self) }
        return .aliased(.table(TableRef(schema: schema, table: table, partitions: partitions)), name: alias)
    }
}

extension DataSource: QuerySource {
    public var querySource: DataSource { self }
}

public extension QuerySource {
    func selectAll() -> SelectQuery {
        SelectQuery(projection: [.wildcard()], source: querySource)
    }

    func select(_ column: String, _ columns: String...) -> SelectQuery {
        select(columns: [column] + columns)
    }

    func select(_ item: ProjectionItem, _ items: ProjectionItem...) -> SelectQuery {
        select(projection: [item] + items)
    }

    func select(columns: [String]) -> SelectQuery {
        select(projection: columns.map { ProjectionItem(.column(ColumnRef($0))) })
    }

    func select(projection: [ProjectionItem]) -> SelectQuery {
        SelectQuery(projection: projection.isEmpty ? [.wildcard()] : projection, source: querySource)
    }
}
