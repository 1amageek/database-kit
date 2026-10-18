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
    public let declaredType: DataType

    public init(id: String, namespaceID: String, name: String, start: Int64,
                increment: Int64, minimum: Int64, maximum: Int64,
                cycle: Bool = false, ownedBy: SQLSequenceOwner? = nil,
                declaredType: DataType = .bigint) throws(SQLCatalogError) {
        try SQLIdentifier.validate(id)
        try SQLIdentifier.validate(namespaceID)
        try SQLIdentifier.validate(name)
        let typeMinimum: Int64
        let typeMaximum: Int64
        switch declaredType {
        case .smallint: typeMinimum = Int64(Int16.min); typeMaximum = Int64(Int16.max)
        case .integer: typeMinimum = Int64(Int32.min); typeMaximum = Int64(Int32.max)
        case .bigint: typeMinimum = .min; typeMaximum = .max
        default: throw .invalidSequenceType
        }
        guard increment != 0 else { throw .invalidSequenceIncrement }
        guard minimum < maximum, minimum >= typeMinimum, maximum <= typeMaximum else { throw .invalidSequenceBounds }
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
        self.declaredType = declaredType
    }
}
