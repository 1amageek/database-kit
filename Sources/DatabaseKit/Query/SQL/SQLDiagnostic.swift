/// Portable SQL failure metadata; the runtime retains the native cause separately.
public struct SQLDiagnostic: Sendable, Hashable {
    public let sqlState: String
    public let category: SQLDiagnosticCategory
    public let message: String
    public let position: UInt64?
    public let schema: String?
    public let table: String?
    public let column: String?
    public let constraint: String?

    public init(sqlState: String, category: SQLDiagnosticCategory, message: String,
        position: UInt64? = nil, schema: String? = nil, table: String? = nil,
        column: String? = nil, constraint: String? = nil) throws(SQLDiagnosticError) {
        guard sqlState.utf8.count == 5, sqlState.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0)
        }) else { throw .invalidSQLState }
        guard position != 0 else { throw .invalidPosition }
        self.sqlState = sqlState
        self.category = category
        self.message = message
        self.position = position
        self.schema = schema
        self.table = table
        self.column = column
        self.constraint = constraint
    }
}
