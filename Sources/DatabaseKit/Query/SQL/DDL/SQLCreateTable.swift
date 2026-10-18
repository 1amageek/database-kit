/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLCreateTable: Sendable, Hashable {
    public let name: TableRef
    public let source: SQLTableDefinition
    public let temporary: Bool
    public let ifNotExists: Bool

    public init(name: TableRef, source: SQLTableDefinition, temporary: Bool = false, ifNotExists: Bool = false) {
        self.name = name
        self.source = source
        self.temporary = temporary
        self.ifNotExists = ifNotExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.source, rhs.source)
            && SQLDDLIdentity.equal(lhs.temporary, rhs.temporary)
            && SQLDDLIdentity.equal(lhs.ifNotExists, rhs.ifNotExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(source, into: &hasher)
        SQLDDLIdentity.hash(temporary, into: &hasher)
        SQLDDLIdentity.hash(ifNotExists, into: &hasher)
    }
}
