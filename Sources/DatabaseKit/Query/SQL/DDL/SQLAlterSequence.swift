/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLAlterSequence: Sendable, Hashable {
    public let name: TableRef
    public let options: SQLSequenceOptions
    public let restart: SQLSequenceRestart?
    public let ownedBy: SQLSequenceOwnership?
    public let renameTo: String?
    public let ifExists: Bool

    public init(name: TableRef, options: SQLSequenceOptions = SQLSequenceOptions(), restart: SQLSequenceRestart? = nil, ownedBy: SQLSequenceOwnership? = nil, renameTo: String? = nil, ifExists: Bool = false) {
        self.name = name
        self.options = options
        self.restart = restart
        self.ownedBy = ownedBy
        self.renameTo = renameTo
        self.ifExists = ifExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.options, rhs.options)
            && SQLDDLIdentity.equal(lhs.restart, rhs.restart)
            && SQLDDLIdentity.equal(lhs.ownedBy, rhs.ownedBy)
            && SQLDDLIdentity.equal(lhs.renameTo, rhs.renameTo)
            && SQLDDLIdentity.equal(lhs.ifExists, rhs.ifExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(options, into: &hasher)
        SQLDDLIdentity.hash(restart, into: &hasher)
        SQLDDLIdentity.hash(ownedBy, into: &hasher)
        SQLDDLIdentity.hash(renameTo, into: &hasher)
        SQLDDLIdentity.hash(ifExists, into: &hasher)
    }
}
