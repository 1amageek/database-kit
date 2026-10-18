/// A named ordinary statement whose parameters have an independent definition scope.
public struct SQLPrepare: Sendable, Hashable {
    public let name: String
    public let parameterTypes: [DataType]
    public let statement: QueryStatement

    public init(name: String, parameterTypes: [DataType] = [], statement: QueryStatement) {
        self.name = name; self.parameterTypes = parameterTypes; self.statement = statement
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard SQLDDLIdentity.equal(lhs.name, rhs.name), lhs.parameterTypes.count == rhs.parameterTypes.count,
              lhs.statement == rhs.statement else { return false }
        for index in lhs.parameterTypes.indices {
            if !equalType(lhs.parameterTypes[index], rhs.parameterTypes[index]) { return false }
        }
        return true
    }
    public func hash(into hasher: inout Hasher) {
        SQLDDLIdentity.hash(name, into: &hasher)
        hasher.combine(parameterTypes.count)
        for type in parameterTypes { Self.hashType(type, into: &hasher) }
        hasher.combine(statement)
    }

    private static func equalType(_ lhs: DataType, _ rhs: DataType) -> Bool {
        var left = lhs
        var right = rhs
        while true {
            switch (left, right) {
            case (.array(let l), .array(let r)): left = l; right = r
            case (.custom(let ln, let ls), .custom(let rn, let rs)):
                return SQLDDLIdentity.equal(ln, rn) && SQLDDLIdentity.equal(ls, rs)
            case (.array, _), (_, .array): return false
            default: return left == right
            }
        }
    }

    private static func hashType(_ type: DataType, into hasher: inout Hasher) {
        var current = type
        while true {
            switch current {
            case .array(let element): hasher.combine(0); current = element
            case .custom(let name, let schema):
                hasher.combine(1); SQLDDLIdentity.hash(name, into: &hasher)
                SQLDDLIdentity.hash(schema, into: &hasher); return
            default: hasher.combine(2); hasher.combine(current); return
            }
        }
    }
}
