/// Immutable resolved SQL catalog metadata; execution and persistence are runtime-owned.
public struct SQLSequenceBinding: Sendable, Hashable {
    public let originalName: String
    public let sequenceID: String

    public init(originalName: String, sequenceID: String) throws(SQLCatalogError) {
        try SQLIdentifier.validate(originalName)
        try SQLIdentifier.validate(sequenceID)
        self.originalName = originalName
        self.sequenceID = sequenceID
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        SQLIdentifier(value: lhs.originalName) == SQLIdentifier(value: rhs.originalName)
            && SQLIdentifier(value: lhs.sequenceID) == SQLIdentifier(value: rhs.sequenceID)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(SQLIdentifier(value: originalName))
        hasher.combine(SQLIdentifier(value: sequenceID))
    }
}
