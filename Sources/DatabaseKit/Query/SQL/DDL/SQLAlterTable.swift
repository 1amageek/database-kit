/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLAlterTable: Sendable, Hashable {
    public let name: TableRef
    public let actions: [SQLAlterTableAction]
    public let ifExists: Bool

    public init(name: TableRef, actions: [SQLAlterTableAction], ifExists: Bool = false) {
        self.name = name
        self.actions = actions
        self.ifExists = ifExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.actions, rhs.actions)
            && SQLDDLIdentity.equal(lhs.ifExists, rhs.ifExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(actions, into: &hasher)
        SQLDDLIdentity.hash(ifExists, into: &hasher)
    }
}
