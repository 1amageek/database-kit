/// The named or complete set of constraints whose request timing changes.
public enum SQLConstraintSelection: Sendable, Hashable {
    case all
    case named([String])

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all): return true
        case (.named(let left), .named(let right)):
            return SQLIdentifier.equal(left, right)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .all: hasher.combine(0)
        case .named(let names):
            hasher.combine(1); hasher.combine(names.count)
            for name in names { hasher.combine(SQLIdentifier(value: name)) }
        }
    }
}
