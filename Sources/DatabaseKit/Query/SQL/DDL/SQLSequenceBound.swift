/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLSequenceBound: Sendable, Hashable {
    case value(Int64)
    case none

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.value(let l0), .value(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.none, .none): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .value(let v0):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .none:
            hasher.combine(1)
        }
    }
}
