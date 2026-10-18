/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLViewSourceBinding: Sendable, Hashable {
    public let schema: String?
    public let table: String
    public let relationID: String
    public let columns: [SQLViewColumnBinding]

    public init(schema: String? = nil, table: String, relationID: String, columns: [SQLViewColumnBinding]) throws(SQLCatalogError) {
        if let schema { try SQLIdentifier.validate(schema) }
        try SQLIdentifier.validate(table)
        try SQLIdentifier.validate(relationID)
        try SQLCatalogMetadataValidation.columns(columns.map { ($0.id, $0.name) })
        self.schema = schema
        self.table = table
        self.relationID = relationID
        self.columns = columns
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.nameEqual(lhs.schema, rhs.schema)
            && SQLIdentifier(value: lhs.table) == SQLIdentifier(value: rhs.table)
            && SQLIdentifier(value: lhs.relationID) == SQLIdentifier(value: rhs.relationID)
            && lhs.columns == rhs.columns
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hashName(schema, into: &hasher)
        hasher.combine(SQLIdentifier(value: table))
        hasher.combine(SQLIdentifier(value: relationID))
        hasher.combine(columns)
    }
}
