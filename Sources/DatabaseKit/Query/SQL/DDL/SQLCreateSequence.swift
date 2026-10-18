/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLCreateSequence: Sendable, Hashable {
    public let name: TableRef
    public let options: SQLSequenceOptions
    public let ownedBy: SQLSequenceOwnership?
    public let ifNotExists: Bool

    public init(name: TableRef, options: SQLSequenceOptions = SQLSequenceOptions(), ownedBy: SQLSequenceOwnership? = nil, ifNotExists: Bool = false) {
        self.name = name
        self.options = options
        self.ownedBy = ownedBy
        self.ifNotExists = ifNotExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.options, rhs.options)
            && SQLDDLIdentity.equal(lhs.ownedBy, rhs.ownedBy)
            && SQLDDLIdentity.equal(lhs.ifNotExists, rhs.ifNotExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(options, into: &hasher)
        SQLDDLIdentity.hash(ownedBy, into: &hasher)
        SQLDDLIdentity.hash(ifNotExists, into: &hasher)
    }
}
