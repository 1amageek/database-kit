/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLSequenceOwnership: Sendable, Hashable {
    case none
    case column(table: TableRef, column: String)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.column(let l0, let l1), .column(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .none:
            hasher.combine(0)
        case .column(let v0, let v1):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        }
    }
}
