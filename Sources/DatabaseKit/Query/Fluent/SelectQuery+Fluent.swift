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
}
