public struct RecordIdentity: Sendable, Hashable {
    public let entity: String
    public let id: RecordIdentifierValue
    public let partitions: [DatabaseObjectField]

    public init(
        entity: String,
        id: RecordIdentifierValue,
        partitions: [DatabaseObjectField] = []
    ) {
        self.entity = entity
        self.id = id
        self.partitions = partitions
    }
}
