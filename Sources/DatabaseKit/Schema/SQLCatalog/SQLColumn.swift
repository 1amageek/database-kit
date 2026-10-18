/// A logical SQL column whose stable ID is independent of physical field number.
public struct SQLColumn: Sendable, Hashable {
    public let id: String
    public let name: String
    public let backing: SQLColumnBacking
    public let policy: SQLColumnPolicy
    public let sequenceBindings: [SQLSequenceBinding]
    public var fieldNumber: Int? {
        if case .field(let number) = backing { return number }
        return nil
    }

    public init(id: String, name: String, fieldNumber: Int) throws(SQLCatalogError) {
        try self.init(id: id, name: name, backing: .field(number: fieldNumber))
    }

    public init(id: String, name: String, backing: SQLColumnBacking,
                policy: SQLColumnPolicy = .input(defaultExpression: nil),
                sequenceBindings: [SQLSequenceBinding] = []) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        switch backing {
        case .field(let number):
            guard number > 0 else { throw .invalidFieldNumber(number) }
        case .virtual(let type):
            guard case .generated = policy else { throw .invalidColumnPolicy(id) }
            guard QueryValueValidator.accepts(.primitive(.null), type: type) else {
                throw .invalidColumnType(id)
            }
        }
        var sequenceNames: Set<SQLIdentifier> = []
        for binding in sequenceBindings {
            guard sequenceNames.insert(SQLIdentifier(value: binding.originalName)).inserted else { throw .invalidColumnPolicy(id) }
        }
        guard sequenceBindings.isEmpty || { if case .input(.some) = policy { return true }; return false }() else { throw .invalidColumnPolicy(id) }
        self.sequenceBindings = sequenceBindings
        self.id = id
        self.name = name
        self.backing = backing
        self.policy = policy
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.backing == rhs.backing
            && lhs.policy == rhs.policy
            && lhs.sequenceBindings == rhs.sequenceBindings
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(backing)
        hasher.combine(policy)
        hasher.combine(sequenceBindings)
    }
}
