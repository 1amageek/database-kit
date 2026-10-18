/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLCreateView: Sendable, Hashable {
    public let name: TableRef
    public let columns: [String]?
    public let query: SelectQuery
    public let orReplace: Bool

    public init(name: TableRef, columns: [String]? = nil, query: SelectQuery, orReplace: Bool = false) {
        self.name = name
        self.columns = columns
        self.query = query
        self.orReplace = orReplace
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.columns, rhs.columns)
            && SQLDDLIdentity.equal(lhs.query, rhs.query)
            && SQLDDLIdentity.equal(lhs.orReplace, rhs.orReplace)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(columns, into: &hasher)
        SQLDDLIdentity.hash(query, into: &hasher)
        SQLDDLIdentity.hash(orReplace, into: &hasher)
    }
}
