import DatabaseTypes

extension EntityReference: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case entity
        case id
        case partitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            entity: container.decode(String.self, forKey: .entity),
            id: container.decode(ReferenceIdentifier.self, forKey: .id),
            partitions: container.decode(FieldObject.self, forKey: .partitions)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entity, forKey: .entity)
        try container.encode(id, forKey: .id)
        try container.encode(partitions, forKey: .partitions)
    }
}
