/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLCreateIndex: Sendable, Hashable {
    public let name: TableRef
    public let table: TableRef
    public let keys: [SortKey]
    public let predicate: Expression?
    public let unique: Bool
    public let nulls: SQLNullUniqueness
    public let ifNotExists: Bool

    public init(name: TableRef, table: TableRef, keys: [SortKey], predicate: Expression? = nil, unique: Bool = false, nulls: SQLNullUniqueness = .distinct, ifNotExists: Bool = false) {
        self.name = name
        self.table = table
        self.keys = keys
        self.predicate = predicate
        self.unique = unique
        self.nulls = nulls
        self.ifNotExists = ifNotExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.table, rhs.table)
            && SQLDDLIdentity.equal(lhs.keys, rhs.keys)
            && SQLDDLIdentity.equal(lhs.predicate, rhs.predicate)
            && SQLDDLIdentity.equal(lhs.unique, rhs.unique)
            && SQLDDLIdentity.equal(lhs.nulls, rhs.nulls)
            && SQLDDLIdentity.equal(lhs.ifNotExists, rhs.ifNotExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(table, into: &hasher)
        SQLDDLIdentity.hash(keys, into: &hasher)
        SQLDDLIdentity.hash(predicate, into: &hasher)
        SQLDDLIdentity.hash(unique, into: &hasher)
        SQLDDLIdentity.hash(nulls, into: &hasher)
        SQLDDLIdentity.hash(ifNotExists, into: &hasher)
    }
}
