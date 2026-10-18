/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLSequenceOptions: Sendable, Hashable {
    public let type: DataType?
    public let start: Int64?
    public let increment: Int64?
    public let minimum: SQLSequenceBound?
    public let maximum: SQLSequenceBound?
    public let cycle: Bool?

    public init(type: DataType? = nil, start: Int64? = nil, increment: Int64? = nil, minimum: SQLSequenceBound? = nil, maximum: SQLSequenceBound? = nil, cycle: Bool? = nil) {
        self.type = type
        self.start = start
        self.increment = increment
        self.minimum = minimum
        self.maximum = maximum
        self.cycle = cycle
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.type, rhs.type)
            && SQLDDLIdentity.equal(lhs.start, rhs.start)
            && SQLDDLIdentity.equal(lhs.increment, rhs.increment)
            && SQLDDLIdentity.equal(lhs.minimum, rhs.minimum)
            && SQLDDLIdentity.equal(lhs.maximum, rhs.maximum)
            && SQLDDLIdentity.equal(lhs.cycle, rhs.cycle)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(type, into: &hasher)
        SQLDDLIdentity.hash(start, into: &hasher)
        SQLDDLIdentity.hash(increment, into: &hasher)
        SQLDDLIdentity.hash(minimum, into: &hasher)
        SQLDDLIdentity.hash(maximum, into: &hasher)
        SQLDDLIdentity.hash(cycle, into: &hasher)
    }
}
