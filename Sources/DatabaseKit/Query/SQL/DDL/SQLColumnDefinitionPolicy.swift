/// Closed SQL declaration alternatives before catalog resolution.
public enum SQLColumnDefinitionPolicy: Sendable, Hashable {
    case input(defaultExpression: Expression?)
    case generated(Expression, stored: Bool)
    case identity(generation: SQLIdentityGeneration, options: SQLSequenceOptions)
    case serial

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.input(let l0), .input(let r0)): return SQLDDLIdentity.equal(l0, r0)
        case (.generated(let l0, let l1), .generated(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.identity(let l0, let l1), .identity(let r0, let r1)): return SQLDDLIdentity.equal(l0, r0) && SQLDDLIdentity.equal(l1, r1)
        case (.serial, .serial): return true
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .input(let v0):
            hasher.combine(0)
            SQLDDLIdentity.hash(v0, into: &hasher)
        case .generated(let v0, let v1):
            hasher.combine(1)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .identity(let v0, let v1):
            hasher.combine(2)
            SQLDDLIdentity.hash(v0, into: &hasher)
            SQLDDLIdentity.hash(v1, into: &hasher)
        case .serial:
            hasher.combine(3)
        }
    }
}
