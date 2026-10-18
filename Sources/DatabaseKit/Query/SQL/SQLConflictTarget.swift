/// The SQL unique arbiter selected by an INSERT conflict clause.
public enum SQLConflictTarget: Sendable, Equatable, Hashable {
    case columns([String], where: Expression?)
    case constraint(String)
}

extension SQLConflictTarget {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.columns(let a, let x), .columns(let b, let y)):
            return ExpressionIdentity.namesEqual(a, b) && x == y
        case (.constraint(let a), .constraint(let b)): return ExpressionIdentity.nameEqual(a, b)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .columns(let names, let predicate):
            hasher.combine(0); ExpressionIdentity.hashNames(names, into: &hasher); hasher.combine(predicate)
        case .constraint(let name): hasher.combine(1); ExpressionIdentity.hashName(name, into: &hasher)
        }
    }
}
