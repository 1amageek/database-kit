/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLTableConstraintKind: Sendable, Hashable {
    case primaryKey(columns: [String])
    case unique(columns: [String], nulls: SQLNullUniqueness)
    case notNull(column: String)
    case check(Expression)
    case foreignKey(SQLForeignKeyDefinition)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.primaryKey(let l0), .primaryKey(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.unique(let l0, let l1), .unique(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.notNull(let l0), .notNull(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.check(let l0), .check(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.foreignKey(let l0), .foreignKey(let r0)): return SQLDDLIdentity.equal(l0, r0)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .primaryKey(let v0):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .unique(let v0, let v1):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .notNull(let v0):
            hasher.combine(2)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .check(let v0):
            hasher.combine(3)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .foreignKey(let v0):
            hasher.combine(4)
            SQLDDLIdentity.hash(v0, into: &hasher)
        }
    }
}
