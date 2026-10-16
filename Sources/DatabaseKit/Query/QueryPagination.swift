public struct QueryPagination: Sendable, Hashable {
    public let limit: QueryLimit?
    public let offset: QueryCount?

    public init(limit: QueryLimit? = nil, offset: QueryCount? = nil) {
        self.limit = limit
        self.offset = offset
    }
}
