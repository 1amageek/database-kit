/// An immutable signed-integer sequence declaration; consumption is runtime-owned.
public struct SQLSequence: Sendable, Hashable {
    private let identity: SQLIdentifier
    private let namespace: SQLIdentifier
    private let sqlName: SQLIdentifier
    public var id: String { identity.value }
    public var namespaceID: String { namespace.value }
    public var name: String { sqlName.value }
    public let start: Int64
    public let increment: Int64
    public let minimum: Int64
    public let maximum: Int64
    public let cycle: Bool
    public let ownedBy: SQLSequenceOwner?

    public init(id: String, namespaceID: String, name: String, start: Int64,
                increment: Int64, minimum: Int64, maximum: Int64,
                cycle: Bool = false, ownedBy: SQLSequenceOwner? = nil) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        guard increment != 0 else { throw .invalidSequenceIncrement }
        guard minimum < maximum else { throw .invalidSequenceBounds }
        guard start >= minimum, start <= maximum else { throw .invalidSequenceStart }
        self.identity = SQLIdentifier(value: id)
        self.namespace = SQLIdentifier(value: namespaceID)
        self.sqlName = SQLIdentifier(value: name)
        self.start = start
        self.increment = increment
        self.minimum = minimum
        self.maximum = maximum
        self.cycle = cycle
        self.ownedBy = ownedBy
    }
}
