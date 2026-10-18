/// A named relation with ordered columns or an ordinary SELECT output.
public enum SQLCopyTarget: Sendable, Hashable {
    case table(TableRef, columns: [String])
    case query(SelectQuery)
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.table(let lt, let lc), .table(let rt, let rc)):
            return SQLDDLIdentity.equal(lt, rt) && SQLDDLIdentity.equal(lc, rc)
        case (.query(let l), .query(let r)): return l == r
        default: return false
        }
    }
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .table(let table, let columns):
            hasher.combine(0); SQLDDLIdentity.hash(table, into: &hasher); SQLDDLIdentity.hash(columns, into: &hasher)
        case .query(let query): hasher.combine(1); hasher.combine(query)
        }
    }
}
