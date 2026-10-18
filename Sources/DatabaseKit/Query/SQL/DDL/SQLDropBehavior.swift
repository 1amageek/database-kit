/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLDropBehavior: Sendable, Hashable {
    case restrict
    case cascade

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.restrict, .restrict): return true
        case (.cascade, .cascade): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .restrict:
            hasher.combine(0)
        case .cascade:
            hasher.combine(1)
        }
    }
}
