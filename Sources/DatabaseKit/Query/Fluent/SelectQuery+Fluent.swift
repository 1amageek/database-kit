public extension SelectQuery {
    func `where`(_ condition: Expression) -> Self {
        replacing(filter: filter.map { .and($0, condition) } ?? condition)
    }

    func orWhere(_ condition: Expression) -> Self {
        replacing(filter: filter.map { .or($0, condition) } ?? condition)
    }

    func orderBy(_ expression: Expression, _ direction: SortDirection = .ascending) -> Self {
        replacing(orderBy: (orderBy ?? []) + [SortKey(expression, direction: direction)])
    }

    func orderBy(_ column: String, _ direction: SortDirection = .ascending) -> Self {
        orderBy(.column(ColumnRef(column)), direction)
    }

    func limit(_ count: UInt64) -> Self {
        replacing(pagination: QueryPagination(limit: .count(.fixed(count), withTies: false), offset: pagination.offset))
    }

    func offset(_ count: UInt64) -> Self {
        replacing(pagination: QueryPagination(limit: pagination.limit, offset: .fixed(count)))
    }

    func paginate(pageIndex: UInt64, pageSize: UInt64) throws(SelectionConstructionError) -> Self {
        let (offset, overflow) = pageIndex.multipliedReportingOverflow(by: pageSize)
        guard !overflow else { throw .paginationOverflow(pageIndex: pageIndex, pageSize: pageSize) }
        return limit(pageSize).offset(offset)
    }

    func selectAll() -> Self { replacing(projection: [.wildcard()]) }

    func select(_ column: String, _ columns: String...) -> Self {
        select(columns: [column] + columns)
    }

    func select(_ item: ProjectionItem, _ items: ProjectionItem...) -> Self {
        select(projection: [item] + items)
    }

    func select(columns: [String]) -> Self {
        select(projection: columns.map { ProjectionItem(.column(ColumnRef($0))) })
    }

    func select(projection: [ProjectionItem]) -> Self {
        replacing(projection: projection.isEmpty ? [.wildcard()] : projection)
    }

    func selectDistinct(_ columns: String...) -> Self {
        select(columns: columns).replacing(quantifier: .distinct)
    }

    func select(_ column: String, as alias: String) -> Self {
        replacing(projection: [ProjectionItem(.column(ColumnRef(column)), alias: alias)])
    }

    func join(_ table: String, on condition: Expression) -> Self { join(TableRef(table), on: condition) }
    func join(_ table: TableRef, on condition: Expression) -> Self {
        joining(table, type: .inner, condition: .on(condition))
    }
    func leftJoin(_ table: String, on condition: Expression) -> Self { leftJoin(TableRef(table), on: condition) }
    func leftJoin(_ table: TableRef, on condition: Expression) -> Self {
        joining(table, type: .left, condition: .on(condition))
    }
    func rightJoin(_ table: String, on condition: Expression) -> Self { rightJoin(TableRef(table), on: condition) }
    func rightJoin(_ table: TableRef, on condition: Expression) -> Self {
        joining(table, type: .right, condition: .on(condition))
    }
    func join(_ table: String, using columns: String...) -> Self {
        joining(TableRef(table), type: .inner, condition: .using(columns))
    }

    private func joining(_ table: TableRef, type: JoinType, condition: JoinCondition) -> Self {
        replacing(source: .join(JoinClause(type: type, left: source,
            right: table.querySource, condition: condition)))
    }

    func graphTable(_ graphName: String, match pattern: MatchPattern) -> Self {
        replacing(source: .graphTable(GraphTableSource(graphName: graphName, matchPattern: pattern)))
    }

    func graphTable(_ graphName: String, match pattern: MatchPattern,
        columns: [(Expression, String)]) -> Self {
        replacing(source: .graphTable(GraphTableSource(graphName: graphName, matchPattern: pattern,
            columns: columns.map { GraphTableColumn(expression: $0.0, alias: $0.1) })))
    }

    func groupBy(_ columns: String...) -> Self {
        groupBy(elements: columns.map { .expression(.column(ColumnRef($0))) })
    }

    func groupBy(_ expressions: Expression...) -> Self {
        groupBy(elements: expressions.map(GroupingElement.expression))
    }

    func groupBy(elements: [GroupingElement]) -> Self { replacing(groupBy: elements) }
    func having(_ condition: Expression) -> Self { replacing(having: condition) }
    func window(_ definitions: NamedWindow...) -> Self { replacing(windows: definitions) }
    func orderByDesc(_ column: String) -> Self { orderBy(column, .descending) }

    func with(_ name: String, as query: SelectQuery) -> Self { with(NamedSubquery(name: name, query: query)) }
    func with(_ cte: NamedSubquery) -> Self { replacing(subqueries: (subqueries ?? []) + [cte]) }
    func withRecursive(_ enabled: Bool = true) -> Self { replacing(withRecursive: enabled) }

    func count() -> Self { projecting(.count, arguments: []) }
    func sum(_ column: String) -> Self { projecting(.sum, arguments: [.column(ColumnRef(column))]) }
    func avg(_ column: String) -> Self { projecting(.avg, arguments: [.column(ColumnRef(column))]) }
    func max(_ column: String) -> Self { projecting(.max, arguments: [.column(ColumnRef(column))]) }
    func min(_ column: String) -> Self { projecting(.min, arguments: [.column(ColumnRef(column))]) }

    private func projecting(_ function: SQLAggregateFunction, arguments: [Expression]) -> Self {
        replacing(projection: [ProjectionItem(.aggregate(.sql(SQLAggregateCall(
            function: function, arguments: arguments))), alias: function.rawValue)])
    }
}
