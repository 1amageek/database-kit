/// The action selected by one MERGE branch.
public enum SQLMergeAction: Sendable, Equatable, Hashable {
    /// Nil values means DEFAULT VALUES; a present list must be nonempty.
    case insert(columns: [String]?, values: [Expression]?, overriding: SQLIdentityOverride?)
    case update([Assignment])
    case delete
    case doNothing
}

extension SQLMergeAction {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.insert(let a, let x, let p), .insert(let b, let y, let q)):
            return ExpressionIdentity.namesEqual(a, b) && x == y && p == q
        case (.update(let a), .update(let b)): return a == b
        case (.delete, .delete), (.doNothing, .doNothing): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .insert(let columns, let values, let overriding):
            hasher.combine(0); ExpressionIdentity.hashNames(columns, into: &hasher)
            hasher.combine(values); hasher.combine(overriding)
        case .update(let assignments): hasher.combine(1); hasher.combine(assignments)
        case .delete: hasher.combine(2)
        case .doNothing: hasher.combine(3)
        }
    }
}
