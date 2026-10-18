/// Immutable name-based SQL declaration; catalog binding is runtime-owned.
public struct SQLCreateMaterializedView: Sendable, Hashable {
    public let name: TableRef
    public let columns: [String]?
    public let query: SelectQuery
    public let withData: Bool
    public let ifNotExists: Bool

    public init(name: TableRef, columns: [String]? = nil, query: SelectQuery, withData: Bool = true, ifNotExists: Bool = false) {
        self.name = name
        self.columns = columns
        self.query = query
        self.withData = withData
        self.ifNotExists = ifNotExists
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLDDLIdentity.equal(lhs.name, rhs.name)
            && SQLDDLIdentity.equal(lhs.columns, rhs.columns)
            && SQLDDLIdentity.equal(lhs.query, rhs.query)
            && SQLDDLIdentity.equal(lhs.withData, rhs.withData)
            && SQLDDLIdentity.equal(lhs.ifNotExists, rhs.ifNotExists)
    }

    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        SQLDDLIdentity.hash(columns, into: &hasher)
        SQLDDLIdentity.hash(query, into: &hasher)
        SQLDDLIdentity.hash(withData, into: &hasher)
        SQLDDLIdentity.hash(ifNotExists, into: &hasher)
    }
}
