/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLColumnDefinition: Sendable, Hashable {
    public let name: String
    public let type: DataType
    public let policy: SQLColumnDefinitionPolicy
    public let constraints: [SQLTableConstraint]

    public init(name: String, type: DataType, policy: SQLColumnDefinitionPolicy = .input(defaultExpression: nil), constraints: [SQLTableConstraint] = []) {
        self.name = name
        self.type = type
        self.policy = policy
        self.constraints = constraints
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.type, rhs.type)
            && SQLDDLIdentity.equal(lhs.policy, rhs.policy)
            && SQLDDLIdentity.equal(lhs.constraints, rhs.constraints)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(type, into: &hasher)
        SQLDDLIdentity.hash(policy, into: &hasher)
        SQLDDLIdentity.hash(constraints, into: &hasher)
    }
}
