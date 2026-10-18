/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLAlterTableAction: Sendable, Hashable {
    case addColumn(SQLColumnDefinition, ifNotExists: Bool)
    case dropColumn(name: String, ifExists: Bool, behavior: SQLDropBehavior)
    case renameColumn(name: String, to: String)
    case alterColumnType(name: String, type: DataType, using: Expression?)
    case setDefault(column: String, expression: Expression)
    case dropDefault(column: String)
    case setNotNull(column: String)
    case dropNotNull(column: String)
    case addConstraint(SQLTableConstraint)
    case dropConstraint(name: String, ifExists: Bool, behavior: SQLDropBehavior)
    case renameTable(to: String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.addColumn(let l0, let l1), .addColumn(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.dropColumn(let l0, let l1, let l2), .dropColumn(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.renameColumn(let l0, let l1), .renameColumn(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.alterColumnType(let l0, let l1, let l2), .alterColumnType(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.setDefault(let l0, let l1), .setDefault(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.dropDefault(let l0), .dropDefault(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.setNotNull(let l0), .setNotNull(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropNotNull(let l0), .dropNotNull(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.addConstraint(let l0), .addConstraint(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.dropConstraint(let l0, let l1, let l2), .dropConstraint(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        case (.renameTable(let l0), .renameTable(let r0)): return SQLDDLIdentity.equal(l0, r0)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .addColumn(let v0, let v1):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .dropColumn(let v0, let v1, let v2):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .renameColumn(let v0, let v1):
            hasher.combine(2)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .alterColumnType(let v0, let v1, let v2):
            hasher.combine(3)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .setDefault(let v0, let v1):
            hasher.combine(4)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .dropDefault(let v0):
            hasher.combine(5)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .setNotNull(let v0):
            hasher.combine(6)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropNotNull(let v0):
            hasher.combine(7)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .addConstraint(let v0):
            hasher.combine(8)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .dropConstraint(let v0, let v1, let v2):
            hasher.combine(9)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        case .renameTable(let v0):
            hasher.combine(10)
            SQLDDLIdentity.hash(v0, into: &hasher)
        }
    }
}
