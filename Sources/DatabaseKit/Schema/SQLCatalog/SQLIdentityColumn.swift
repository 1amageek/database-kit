/// A column's immutable sequence binding and identity generation policy.
public struct SQLIdentityColumn: Sendable, Hashable {
    private let sequence: SQLIdentifier
    public var sequenceID: String { sequence.value }
    public let generation: SQLIdentityGeneration

    public init(sequenceID: String, generation: SQLIdentityGeneration) throws(SQLCatalogError) {
        try SQLIdentifier.validate(sequenceID)
        self.sequence = SQLIdentifier(value: sequenceID)
        self.generation = generation
    }
}
