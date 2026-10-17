/// Immutable SEARCH keys and generated sequence-column identity.
public struct CTESearchClause: Sendable, Hashable {
    public let order: CTESearchOrder
    public let columns: [String]
    public let sequenceColumn: String

    public init(order: CTESearchOrder, columns: [String], sequenceColumn: String) {
        self.order = order
        self.columns = columns
        self.sequenceColumn = sequenceColumn
    }
}
