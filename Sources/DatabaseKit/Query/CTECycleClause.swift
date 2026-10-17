/// Immutable CYCLE keys, generated columns and optional paired SQL constants.
public struct CTECycleClause: Sendable, Hashable {
    public let columns: [String]
    public let markColumn: String
    public let pathColumn: String
    public let markValue: Literal?
    public let defaultValue: Literal?

    public init(columns: [String], markColumn: String, pathColumn: String,
                markValue: Literal? = nil, defaultValue: Literal? = nil) {
        self.columns = columns
        self.markColumn = markColumn
        self.pathColumn = pathColumn
        self.markValue = markValue
        self.defaultValue = defaultValue
    }
}
