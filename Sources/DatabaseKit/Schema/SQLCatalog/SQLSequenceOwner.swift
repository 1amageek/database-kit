/// A sequence's logical owning column, without a runtime handle.
public struct SQLSequenceOwner: Sendable, Hashable {
    private let relation: SQLIdentifier
    private let column: SQLIdentifier
    public var relationID: String { relation.value }
    public var columnID: String { column.value }

    public init(relationID: String, columnID: String) throws(SQLCatalogError) {
        try SQLIdentifier.validate(relationID)
        try SQLIdentifier.validate(columnID)
        self.relation = SQLIdentifier(value: relationID)
        self.column = SQLIdentifier(value: columnID)
    }
}
