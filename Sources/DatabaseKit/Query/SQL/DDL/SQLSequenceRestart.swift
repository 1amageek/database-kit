/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLSequenceRestart: Sendable, Hashable {
    case start
    case value(Int64)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.start, .start): return true
        case (.value(let l0), .value(let r0)): return SQLDDLIdentity.equal(l0, r0)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .start:
            hasher.combine(0)
        case .value(let v0):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
        }
    }
}
