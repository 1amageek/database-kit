/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLTableConstraint: Sendable, Hashable {
    public let name: String?
    public let timing: SQLConstraintTiming
    public let kind: SQLTableConstraintKind

    public init(name: String? = nil, timing: SQLConstraintTiming = .immediate, kind: SQLTableConstraintKind) {
        self.name = name
        self.timing = timing
        self.kind = kind
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.timing, rhs.timing)
            && SQLDDLIdentity.equal(lhs.kind, rhs.kind)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(timing, into: &hasher)
        SQLDDLIdentity.hash(kind, into: &hasher)
    }
}
