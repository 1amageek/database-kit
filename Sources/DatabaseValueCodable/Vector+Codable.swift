import DatabaseTypes

extension Vector: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case elementType
        case elements
    }

    private enum EncodedElementType: String, Codable {
        case int8
        case int16
        case int32
        case int64
        case uint8
        case uint16
        case uint32
        case uint64
        case float32
        case float64
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(
            EncodedElementType.self,
            forKey: .elementType
        ) {
        case .int8:
            self.init(
                int8: try container.decode([Int8].self, forKey: .elements)
            )
        case .int16:
            self.init(
                int16: try container.decode([Int16].self, forKey: .elements)
            )
        case .int32:
            self.init(
                int32: try container.decode([Int32].self, forKey: .elements)
            )
        case .int64:
            self.init(
                int64: try container.decode([Int64].self, forKey: .elements)
            )
        case .uint8:
            self.init(
                uint8: try container.decode([UInt8].self, forKey: .elements)
            )
        case .uint16:
            self.init(
                uint16: try container.decode([UInt16].self, forKey: .elements)
            )
        case .uint32:
            self.init(
                uint32: try container.decode([UInt32].self, forKey: .elements)
            )
        case .uint64:
            self.init(
                uint64: try container.decode([UInt64].self, forKey: .elements)
            )
        case .float32:
            try self.init(
                float32: container.decode([Float].self, forKey: .elements)
            )
        case .float64:
            try self.init(
                float64: container.decode([Double].self, forKey: .elements)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch elementType {
        case .int8:
            try container.encode(EncodedElementType.int8, forKey: .elementType)
            try encodeElements(
                using: withInt8Elements,
                into: &container
            )
        case .int16:
            try container.encode(EncodedElementType.int16, forKey: .elementType)
            try encodeElements(
                using: withInt16Elements,
                into: &container
            )
        case .int32:
            try container.encode(EncodedElementType.int32, forKey: .elementType)
            try encodeElements(
                using: withInt32Elements,
                into: &container
            )
        case .int64:
            try container.encode(EncodedElementType.int64, forKey: .elementType)
            try encodeElements(
                using: withInt64Elements,
                into: &container
            )
        case .uint8:
            try container.encode(EncodedElementType.uint8, forKey: .elementType)
            try encodeElements(
                using: withUInt8Elements,
                into: &container
            )
        case .uint16:
            try container.encode(EncodedElementType.uint16, forKey: .elementType)
            try encodeElements(
                using: withUInt16Elements,
                into: &container
            )
        case .uint32:
            try container.encode(EncodedElementType.uint32, forKey: .elementType)
            try encodeElements(
                using: withUInt32Elements,
                into: &container
            )
        case .uint64:
            try container.encode(EncodedElementType.uint64, forKey: .elementType)
            try encodeElements(
                using: withUInt64Elements,
                into: &container
            )
        case .float32:
            try container.encode(
                EncodedElementType.float32,
                forKey: .elementType
            )
            try encodeElements(
                using: withFloat32Elements,
                into: &container
            )
        case .float64:
            try container.encode(
                EncodedElementType.float64,
                forKey: .elementType
            )
            try encodeElements(
                using: withFloat64Elements,
                into: &container
            )
        }
    }

    private func encodeElements<Element: Encodable>(
        using borrow: (
            (UnsafeBufferPointer<Element>) throws -> Void
        ) throws -> Void?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        let encoded: Void? = try borrow { elements in
            // Codable encoders require an owned collection at this boundary.
            try container.encode(Array(elements), forKey: .elements)
        }
        precondition(encoded != nil, "Vector element type changed during encoding")
    }
}
