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
        SelectQuery(projection: ([column] + columns).map { ProjectionItem(.column(ColumnRef($0))) },
            source: querySource)
    }

    func select(_ item: ProjectionItem, _ items: ProjectionItem...) -> SelectQuery {
        SelectQuery(projection: [item] + items, source: querySource)
    }
}
