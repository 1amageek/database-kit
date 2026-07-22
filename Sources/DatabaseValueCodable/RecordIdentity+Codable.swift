import DatabaseValue

extension RecordIdentity: Codable {
    private enum CodingKeys: String, CodingKey {
        case entity
        case id
        case partitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entity: try container.decode(String.self, forKey: .entity),
            id: try container.decode(RecordIdentifierValue.self, forKey: .id),
            partitions: try container.decode([DatabaseObjectField].self, forKey: .partitions)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entity, forKey: .entity)
        try container.encode(id, forKey: .id)
        try container.encode(partitions, forKey: .partitions)
    }
}
