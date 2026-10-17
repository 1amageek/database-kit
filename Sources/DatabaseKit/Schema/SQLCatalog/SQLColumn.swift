/// A logical SQL column whose stable ID is independent of physical field number.
public struct SQLColumn: Sendable, Hashable {
    public let id: String
    public let name: String
    public let fieldNumber: Int

    public init(id: String, name: String, fieldNumber: Int) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        guard fieldNumber > 0 else { throw .invalidFieldNumber(fieldNumber) }
        self.id = id
        self.name = name
        self.fieldNumber = fieldNumber
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.id) == SQLIdentifier(value: rhs.id)
            && SQLIdentifier(value: lhs.name) == SQLIdentifier(value: rhs.name)
            && lhs.fieldNumber == rhs.fieldNumber
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: id))
        hasher.combine(SQLIdentifier(value: name))
        hasher.combine(fieldNumber)
    }
}
