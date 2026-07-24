import DatabaseTypes

extension ExactDecimal: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case coefficient
        case scale
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coefficient = try container.decode(
            String.self,
            forKey: .coefficient
        )
        guard let coefficient = Int128(coefficient) else {
            throw DecodingError.dataCorruptedError(
                forKey: .coefficient,
                in: container,
                debugDescription: "Decimal coefficient exceeds Int128"
            )
        }
        self.init(
            coefficient: coefficient,
            scale: try container.decode(Int32.self, forKey: .scale)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(coefficient), forKey: .coefficient)
        try container.encode(scale, forKey: .scale)
    }
}
