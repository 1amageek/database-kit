/// Explicit transition-row aliases in a RETURNING clause.
public struct SQLReturningAliases: Sendable, Equatable, Hashable {
    public let old: String?
    public let new: String?

    public init(old: String? = nil, new: String? = nil) {
        self.old = old
        self.new = new
    }
}

extension SQLReturningAliases {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.nameEqual(lhs.old, rhs.old) && ExpressionIdentity.nameEqual(lhs.new, rhs.new)
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hashName(old, into: &hasher)
        ExpressionIdentity.hashName(new, into: &hasher)
    }
}
