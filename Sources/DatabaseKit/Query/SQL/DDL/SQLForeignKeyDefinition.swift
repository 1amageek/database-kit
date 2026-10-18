/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLForeignKeyDefinition: Sendable, Hashable {
    public let columns: [String]
    public let referencedTable: TableRef
    public let referencedColumns: [String]?
    public let match: SQLForeignKeyMatch
    public let onUpdate: SQLReferentialAction
    public let onDelete: SQLReferentialAction
    public let onDeleteColumns: [String]?

    public init(columns: [String], referencedTable: TableRef, referencedColumns: [String]? = nil, match: SQLForeignKeyMatch = .simple, onUpdate: SQLReferentialAction = .noAction, onDelete: SQLReferentialAction = .noAction, onDeleteColumns: [String]? = nil) {
        self.columns = columns
        self.referencedTable = referencedTable
        self.referencedColumns = referencedColumns
        self.match = match
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onDeleteColumns = onDeleteColumns
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.columns, rhs.columns)
            && SQLDDLIdentity.equal(lhs.referencedTable, rhs.referencedTable)
            && SQLDDLIdentity.equal(lhs.referencedColumns, rhs.referencedColumns)
            && SQLDDLIdentity.equal(lhs.match, rhs.match)
            && SQLDDLIdentity.equal(lhs.onUpdate, rhs.onUpdate)
            && SQLDDLIdentity.equal(lhs.onDelete, rhs.onDelete)
            && SQLDDLIdentity.equal(lhs.onDeleteColumns, rhs.onDeleteColumns)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(columns, into: &hasher)
        SQLDDLIdentity.hash(referencedTable, into: &hasher)
        SQLDDLIdentity.hash(referencedColumns, into: &hasher)
        SQLDDLIdentity.hash(match, into: &hasher)
        SQLDDLIdentity.hash(onUpdate, into: &hasher)
        SQLDDLIdentity.hash(onDelete, into: &hasher)
        SQLDDLIdentity.hash(onDeleteColumns, into: &hasher)
    }
}
