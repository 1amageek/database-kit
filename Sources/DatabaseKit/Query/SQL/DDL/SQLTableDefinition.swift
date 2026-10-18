/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLTableDefinition: Sendable, Hashable {
    case columns([SQLColumnDefinition], constraints: [SQLTableConstraint])
    case query(SelectQuery, columns: [String]?, withData: Bool)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.columns(let l0, let l1), .columns(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.query(let l0, let l1, let l2), .query(let r0, let r1, let r2)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1) && SQLDDLIdentity.equal(l2, r2)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .columns(let v0, let v1):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .query(let v0, let v1, let v2):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
            SQLDDLIdentity.hash(v2, into: &hasher)
        }
    }
}
