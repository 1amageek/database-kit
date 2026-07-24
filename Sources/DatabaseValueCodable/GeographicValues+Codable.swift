import DatabaseTypes

extension GeographicPoint: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            latitude: container.decode(Double.self, forKey: .latitude),
            longitude: container.decode(Double.self, forKey: .longitude)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }
}

extension GeographicPosition: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case point
        case ellipsoidalHeightInMeters
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            point: container.decode(
                GeographicPoint.self,
                forKey: .point
            ),
            ellipsoidalHeightInMeters: container.decode(
                Double.self,
                forKey: .ellipsoidalHeightInMeters
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(point, forKey: .point)
        try container.encode(
            ellipsoidalHeightInMeters,
            forKey: .ellipsoidalHeightInMeters
        )
    }
}
