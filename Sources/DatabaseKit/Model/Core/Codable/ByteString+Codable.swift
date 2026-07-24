import DatabaseTypes

extension ByteString: @retroactive Codable {
    public init(from decoder: any Decoder) throws {
        self.init(try [UInt8](from: decoder))
    }

    public func encode(to encoder: any Encoder) throws {
        // Codable requires an independently owned collection at this boundary.
        try copyBytes().encode(to: encoder)
    }
}
