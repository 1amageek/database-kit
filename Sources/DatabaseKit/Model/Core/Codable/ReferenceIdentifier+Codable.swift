import DatabaseTypes

extension ReferenceIdentifier: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case bool
        case int8
        case int16
        case int32
        case int64
        case uint8
        case uint16
        case uint32
        case uint64
        case string
        case bytes
        case high
        case low
        case components
    }

    private enum Kind: String, Codable {
        case bool
        case int8
        case int16
        case int32
        case int64
        case uint8
        case uint16
        case uint32
        case uint64
        case string
        case bytes
        case uuid
        case composite
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .bool))
        case .int8:
            self = .int8(try container.decode(Int8.self, forKey: .int8))
        case .int16:
            self = .int16(try container.decode(Int16.self, forKey: .int16))
        case .int32:
            self = .int32(try container.decode(Int32.self, forKey: .int32))
        case .int64:
            self = .int64(try container.decode(Int64.self, forKey: .int64))
        case .uint8:
            self = .uint8(try container.decode(UInt8.self, forKey: .uint8))
        case .uint16:
            self = .uint16(try container.decode(UInt16.self, forKey: .uint16))
        case .uint32:
            self = .uint32(try container.decode(UInt32.self, forKey: .uint32))
        case .uint64:
            self = .uint64(try container.decode(UInt64.self, forKey: .uint64))
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .bytes:
            self = .bytes(
                ByteString(
                    try container.decode([UInt8].self, forKey: .bytes)
                )
            )
        case .uuid:
            self = .uuid(
                DatabaseTypes.UUID(
                    high: try container.decode(UInt64.self, forKey: .high),
                    low: try container.decode(UInt64.self, forKey: .low)
                )
            )
        case .composite:
            let components = try container.decode(
                [ReferenceIdentifier].self,
                forKey: .components
            )
            guard !components.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .components,
                    in: container,
                    debugDescription: "A composite reference identifier must contain at least one component."
                )
            }
            self = .composite(components)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let value):
            try container.encode(Kind.bool, forKey: .kind)
            try container.encode(value, forKey: .bool)
        case .int8(let value):
            try container.encode(Kind.int8, forKey: .kind)
            try container.encode(value, forKey: .int8)
        case .int16(let value):
            try container.encode(Kind.int16, forKey: .kind)
            try container.encode(value, forKey: .int16)
        case .int32(let value):
            try container.encode(Kind.int32, forKey: .kind)
            try container.encode(value, forKey: .int32)
        case .int64(let value):
            try container.encode(Kind.int64, forKey: .kind)
            try container.encode(value, forKey: .int64)
        case .uint8(let value):
            try container.encode(Kind.uint8, forKey: .kind)
            try container.encode(value, forKey: .uint8)
        case .uint16(let value):
            try container.encode(Kind.uint16, forKey: .kind)
            try container.encode(value, forKey: .uint16)
        case .uint32(let value):
            try container.encode(Kind.uint32, forKey: .kind)
            try container.encode(value, forKey: .uint32)
        case .uint64(let value):
            try container.encode(Kind.uint64, forKey: .kind)
            try container.encode(value, forKey: .uint64)
        case .string(let value):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case .bytes(let value):
            try container.encode(Kind.bytes, forKey: .kind)
            // Codable requires an independently owned byte collection at this boundary.
            try container.encode(value.copyBytes(), forKey: .bytes)
        case .uuid(let value):
            try container.encode(Kind.uuid, forKey: .kind)
            try container.encode(value.high, forKey: .high)
            try container.encode(value.low, forKey: .low)
        case .composite(let components):
            guard !components.isEmpty else {
                throw EncodingError.invalidValue(
                    self,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "A composite reference identifier must contain at least one component."
                    )
                )
            }
            try container.encode(Kind.composite, forKey: .kind)
            try container.encode(components, forKey: .components)
        }
    }
}
