/// Immutable query envelope shared by SQL and SPARQL.
public struct SelectQuery: Sendable, Hashable {
    public let projection: [ProjectionItem]
    public let source: DataSource
    public let accessPath: AccessPath?
    public let filter: Expression?
    public let groupBy: [GroupingElement]?
    public let having: Expression?
    public let windows: [NamedWindow]
    public let orderBy: [SortKey]?
    public let quantifier: SelectQuantifier
    public let pagination: QueryPagination
    public let subqueries: [NamedSubquery]?
    public let reduced: Bool
    public let dataset: SPARQLDataset

    public init(
        projection: [ProjectionItem],
        source: DataSource,
        accessPath: AccessPath? = nil,
        filter: Expression? = nil,
        groupBy: [GroupingElement]? = nil,
        having: Expression? = nil,
        windows: [NamedWindow] = [],
        orderBy: [SortKey]? = nil,
        quantifier: SelectQuantifier = .all,
        pagination: QueryPagination = QueryPagination(),
        subqueries: [NamedSubquery]? = nil,
        reduced: Bool = false,
        dataset: SPARQLDataset = .implicit
    ) {
        self.projection = projection
        self.source = source
        self.accessPath = accessPath
        self.filter = filter
        self.groupBy = groupBy
        self.having = having
        self.windows = windows
        self.orderBy = orderBy
        self.quantifier = quantifier
        self.pagination = pagination
        self.subqueries = subqueries
        self.reduced = reduced
        self.dataset = dataset
    }

    public static func == (lhs: SelectQuery, rhs: SelectQuery) -> Bool {
        ExpressionIdentity.areEqual(lhs, rhs)
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hash(self, into: &hasher)
    }
}

extension SelectQuery {
    public func replacing(projection: [ProjectionItem]) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(source: DataSource) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(accessPath: AccessPath?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(filter: Expression?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(groupBy: [GroupingElement]?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(having: Expression?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(windows: [NamedWindow]) -> SelectQuery {
        SelectQuery(projection: projection, source: source, accessPath: accessPath,
            filter: filter, groupBy: groupBy, having: having, windows: windows,
            orderBy: orderBy, quantifier: quantifier, pagination: pagination,
            subqueries: subqueries, reduced: reduced, dataset: dataset)
    }

    public func replacing(orderBy: [SortKey]?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(quantifier: SelectQuantifier) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(pagination: QueryPagination) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(subqueries: [NamedSubquery]?) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(reduced: Bool) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

    public func replacing(dataset: SPARQLDataset) -> SelectQuery {
        SelectQuery(
            projection: projection,
            source: source,
            accessPath: accessPath,
            filter: filter,
            groupBy: groupBy,
            having: having,
            windows: windows,
            orderBy: orderBy,
            quantifier: quantifier,
            pagination: pagination,
            subqueries: subqueries,
            reduced: reduced,
            dataset: dataset
        )
    }

}

extension SelectQuery {
    public var referencedVariables: Set<String> { QueryReferenceCollector.collect(self).variables }
    public var referencedColumns: Set<ColumnRef> { QueryReferenceCollector.collect(self).columns }
    public var hasAggregation: Bool { groupBy?.isEmpty == false }
}
