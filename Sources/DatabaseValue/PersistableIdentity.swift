public struct PersistableIdentity: Sendable {
    public let entity: String
    public let id: PersistableIdentifierValue
    public let partitions: [DatabaseObjectField]

    public init(
        entity: String,
        id: PersistableIdentifierValue,
        partitions: [DatabaseObjectField] = []
    ) {
        self.entity = entity
        self.id = id
        self.partitions = partitions
    }
}
