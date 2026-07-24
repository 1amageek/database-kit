import DatabaseValue

extension FieldValue: Codable {
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
        case float32
        case float64
        case coefficient
        case scale
        case string
        case bytes
        case year
        case month
        case day
        case seconds
        case nanoseconds
        case high
        case low
        case values
        case fields
        case identity
        case term
    }

    private enum EncodedValueKind: String, Codable {
        case null
        case bool
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
        case decimal
        case string
        case bytes
        case date
        case timestamp
        case uuid
        case array
        case object
        case reference
        case rdfTerm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodedValueKind.self, forKey: .kind) {
        case .null:
            self = .null
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
        case .float32:
            self = .float32(try container.decode(Float.self, forKey: .float32))
        case .float64:
            self = .float64(try container.decode(Double.self, forKey: .float64))
        case .decimal:
            self = .decimal(
                coefficient: try container.decode(Int64.self, forKey: .coefficient),
                scale: try container.decode(Int32.self, forKey: .scale)
            )
        case .string:
            self = .string(try container.decode(String.self, forKey: .string))
        case .bytes:
            self = .bytes(
                DatabaseBytes(
                    try container.decode([UInt8].self, forKey: .bytes)
                )
            )
        case .date:
            self = .date(
                DatabaseDate(
                    year: try container.decode(Int32.self, forKey: .year),
                    month: try container.decode(UInt8.self, forKey: .month),
                    day: try container.decode(UInt8.self, forKey: .day)
                )
            )
        case .timestamp:
            self = .timestamp(
                DatabaseTimestamp(
                    secondsSinceUnixEpoch: try container.decode(Int64.self, forKey: .seconds),
                    nanoseconds: try container.decode(UInt32.self, forKey: .nanoseconds)
                )
            )
        case .uuid:
            self = .uuid(
                DatabaseUUID(
                    high: try container.decode(UInt64.self, forKey: .high),
                    low: try container.decode(UInt64.self, forKey: .low)
                )
            )
        case .array:
            self = .array(try container.decode([FieldValue].self, forKey: .values))
        case .object:
            self = .object(try container.decode([DatabaseObjectField].self, forKey: .fields))
        case .reference:
            self = .reference(try container.decode(PersistableIdentity.self, forKey: .identity))
        case .rdfTerm:
            self = .rdfTerm(try container.decode(DatabaseRDFTerm.self, forKey: .term))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(EncodedValueKind.null, forKey: .kind)
        case .bool(let value):
            try container.encode(EncodedValueKind.bool, forKey: .kind)
            try container.encode(value, forKey: .bool)
        case .int8(let value):
            try container.encode(EncodedValueKind.int8, forKey: .kind)
            try container.encode(value, forKey: .int8)
        case .int16(let value):
            try container.encode(EncodedValueKind.int16, forKey: .kind)
            try container.encode(value, forKey: .int16)
        case .int32(let value):
            try container.encode(EncodedValueKind.int32, forKey: .kind)
            try container.encode(value, forKey: .int32)
        case .int64(let value):
            try container.encode(EncodedValueKind.int64, forKey: .kind)
            try container.encode(value, forKey: .int64)
        case .uint8(let value):
            try container.encode(EncodedValueKind.uint8, forKey: .kind)
            try container.encode(value, forKey: .uint8)
        case .uint16(let value):
            try container.encode(EncodedValueKind.uint16, forKey: .kind)
            try container.encode(value, forKey: .uint16)
        case .uint32(let value):
            try container.encode(EncodedValueKind.uint32, forKey: .kind)
            try container.encode(value, forKey: .uint32)
        case .uint64(let value):
            try container.encode(EncodedValueKind.uint64, forKey: .kind)
            try container.encode(value, forKey: .uint64)
        case .float32(let value):
            try container.encode(EncodedValueKind.float32, forKey: .kind)
            try container.encode(value, forKey: .float32)
        case .float64(let value):
            try container.encode(EncodedValueKind.float64, forKey: .kind)
            try container.encode(value, forKey: .float64)
        case .decimal(let coefficient, let scale):
            try container.encode(EncodedValueKind.decimal, forKey: .kind)
            try container.encode(coefficient, forKey: .coefficient)
            try container.encode(scale, forKey: .scale)
        case .string(let value):
            try container.encode(EncodedValueKind.string, forKey: .kind)
            try container.encode(value, forKey: .string)
        case .bytes(let value):
            try container.encode(EncodedValueKind.bytes, forKey: .kind)
            try container.encode(value.copyBytes(), forKey: .bytes)
        case .date(let value):
            try container.encode(EncodedValueKind.date, forKey: .kind)
            try container.encode(value.year, forKey: .year)
            try container.encode(value.month, forKey: .month)
            try container.encode(value.day, forKey: .day)
        case .timestamp(let value):
            try container.encode(EncodedValueKind.timestamp, forKey: .kind)
            try container.encode(value.secondsSinceUnixEpoch, forKey: .seconds)
            try container.encode(value.nanoseconds, forKey: .nanoseconds)
        case .uuid(let value):
            try container.encode(EncodedValueKind.uuid, forKey: .kind)
            try container.encode(value.high, forKey: .high)
            try container.encode(value.low, forKey: .low)
        case .array(let values):
            try container.encode(EncodedValueKind.array, forKey: .kind)
            try container.encode(values, forKey: .values)
        case .object(let fields):
            try container.encode(EncodedValueKind.object, forKey: .kind)
            try container.encode(fields, forKey: .fields)
        case .reference(let identity):
            try container.encode(EncodedValueKind.reference, forKey: .kind)
            try container.encode(identity, forKey: .identity)
        case .rdfTerm(let term):
            try container.encode(EncodedValueKind.rdfTerm, forKey: .kind)
            try container.encode(term, forKey: .term)
        }
    }
}
