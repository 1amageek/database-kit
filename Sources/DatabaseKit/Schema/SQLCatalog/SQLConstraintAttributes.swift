/// Stable identity, SQL name and checking schedule shared by constraints.
public struct SQLConstraintAttributes: Sendable, Hashable {
    private let identity: SQLIdentifier
    private let sqlName: SQLIdentifier
    public var id: String { identity.value }
    public var name: String { sqlName.value }
    public let timing: SQLConstraintTiming

    public init(id: String, name: String, timing: SQLConstraintTiming = .immediate) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(name)
        self.identity = SQLIdentifier(value: id)
        self.sqlName = SQLIdentifier(value: name)
        self.timing = timing
    }
}
