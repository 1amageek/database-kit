/// The closed logical constraint algebra; primary keys retain the relation's key binding.
public enum SQLConstraintKind: Sendable, Hashable {
    case unique(columnIDs: [String], nulls: SQLNullUniqueness)
    case notNull(columnID: String)
    case check(Expression)
    case foreignKey(SQLForeignKey)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.unique(let l, let ln), .unique(let r, let rn)):
            return SQLIdentifier.equal(l, r) && ln == rn
        case (.notNull(let l), .notNull(let r)):
            return SQLIdentifier(value: l) == SQLIdentifier(value: r)
        case (.check(let l), .check(let r)): return l == r
        case (.foreignKey(let l), .foreignKey(let r)): return l == r
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .unique(let ids, let nulls):
            hasher.combine(0); hasher.combine(ids.count)
            for id in ids { hasher.combine(SQLIdentifier(value: id)) }
            hasher.combine(nulls)
        case .notNull(let id): hasher.combine(1); hasher.combine(SQLIdentifier(value: id))
        case .check(let expression): hasher.combine(2); hasher.combine(expression)
        case .foreignKey(let key): hasher.combine(3); hasher.combine(key)
        }
    }
}
