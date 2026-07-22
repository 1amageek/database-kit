import DatabaseValue

extension DatabaseObjectField: Codable {
    private enum CodingKeys: String, CodingKey {
        case number
        case name
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            number: try container.decode(UInt32.self, forKey: .number),
            name: try container.decode(String.self, forKey: .name),
            value: try container.decode(DatabaseValue.self, forKey: .value)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(name, forKey: .name)
        try container.encode(value, forKey: .value)
    }
}
