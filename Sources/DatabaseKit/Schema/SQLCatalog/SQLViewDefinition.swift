/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLViewDefinition: Sendable, Hashable {
    public let query: SelectQuery
    public let columns: [SQLViewColumn]
    public let bindings: [SQLViewSourceBinding]

    public init(query: SelectQuery, columns: [SQLViewColumn], bindings: [SQLViewSourceBinding]) throws(SQLCatalogError) {
        try SQLCatalogMetadataValidation.columns(columns.map { ($0.id, $0.name) })
        var sources: [SQLIdentifier?: Set<SQLIdentifier>] = [:]
        for binding in bindings {
            let schema = binding.schema.map { SQLIdentifier(value: $0) }
            guard sources[schema, default: []].insert(SQLIdentifier(value: binding.table)).inserted else {
                throw .invalidViewDefinition
            }
        }
        self.query = query
        self.columns = columns
        self.bindings = bindings
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query
            && lhs.columns == rhs.columns
            && lhs.bindings == rhs.bindings
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(query)
        hasher.combine(columns)
        hasher.combine(bindings)
    }
}
