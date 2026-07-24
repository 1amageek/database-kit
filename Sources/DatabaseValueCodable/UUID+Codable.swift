import DatabaseTypes

extension DatabaseTypes.UUID: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case high
        case low
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            high: try container.decode(UInt64.self, forKey: .high),
            low: try container.decode(UInt64.self, forKey: .low)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(high, forKey: .high)
        try container.encode(low, forKey: .low)
    }
}
