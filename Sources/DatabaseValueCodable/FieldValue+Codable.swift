import DatabaseTypes

extension FieldValue: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
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
        case time
        case dateTime
        case timestamp
        case timeSpan
        case calendarPeriod
        case geographicPoint
        case geographicPosition
        case vector
        case uuid
        case array
        case object
        case reference
        case rdfTerm
    }

    private struct EncodedUUID: Codable {
        let high: UInt64
        let low: UInt64
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodedValueKind.self, forKey: .kind) {
        case .null:
            self = .null
        case .bool:
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case .int8:
            self = .int8(try container.decode(Int8.self, forKey: .value))
        case .int16:
            self = .int16(try container.decode(Int16.self, forKey: .value))
        case .int32:
            self = .int32(try container.decode(Int32.self, forKey: .value))
        case .int64:
            self = .int64(try container.decode(Int64.self, forKey: .value))
        case .uint8:
            self = .uint8(try container.decode(UInt8.self, forKey: .value))
        case .uint16:
            self = .uint16(try container.decode(UInt16.self, forKey: .value))
        case .uint32:
            self = .uint32(try container.decode(UInt32.self, forKey: .value))
        case .uint64:
            self = .uint64(try container.decode(UInt64.self, forKey: .value))
        case .float32:
            self = .float32(try container.decode(Float.self, forKey: .value))
        case .float64:
            self = .float64(try container.decode(Double.self, forKey: .value))
        case .decimal:
            self = .decimal(
                try container.decode(ExactDecimal.self, forKey: .value)
            )
        case .string:
            self = .string(try container.decode(String.self, forKey: .value))
        case .bytes:
            self = .bytes(
                ByteString(
                    try container.decode([UInt8].self, forKey: .value)
                )
            )
        case .date:
            self = .date(try container.decode(CivilDate.self, forKey: .value))
        case .time:
            self = .time(try container.decode(CivilTime.self, forKey: .value))
        case .dateTime:
            self = .dateTime(
                try container.decode(CivilDateTime.self, forKey: .value)
            )
        case .timestamp:
            self = .timestamp(
                try container.decode(Timestamp.self, forKey: .value)
            )
        case .timeSpan:
            self = .timeSpan(
                try container.decode(TimeSpan.self, forKey: .value)
            )
        case .calendarPeriod:
            self = .calendarPeriod(
                try container.decode(CalendarPeriod.self, forKey: .value)
            )
        case .geographicPoint:
            self = .geographicPoint(
                try container.decode(GeographicPoint.self, forKey: .value)
            )
        case .geographicPosition:
            self = .geographicPosition(
                try container.decode(GeographicPosition.self, forKey: .value)
            )
        case .vector:
            self = .vector(try container.decode(Vector.self, forKey: .value))
        case .uuid:
            let value = try container.decode(
                EncodedUUID.self,
                forKey: .value
            )
            self = .uuid(UUID(high: value.high, low: value.low))
        case .array:
            self = .array(
                try container.decode([FieldValue].self, forKey: .value)
            )
        case .object:
            self = .object(
                try container.decode(FieldObject.self, forKey: .value)
            )
        case .reference:
            self = .reference(
                try container.decode(EntityReference.self, forKey: .value)
            )
        case .rdfTerm:
            self = .rdfTerm(
                try container.decode(RDFTerm.self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(EncodedValueKind.null, forKey: .kind)
        case .bool(let value):
            try encode(.bool, value, into: &container)
        case .int8(let value):
            try encode(.int8, value, into: &container)
        case .int16(let value):
            try encode(.int16, value, into: &container)
        case .int32(let value):
            try encode(.int32, value, into: &container)
        case .int64(let value):
            try encode(.int64, value, into: &container)
        case .uint8(let value):
            try encode(.uint8, value, into: &container)
        case .uint16(let value):
            try encode(.uint16, value, into: &container)
        case .uint32(let value):
            try encode(.uint32, value, into: &container)
        case .uint64(let value):
            try encode(.uint64, value, into: &container)
        case .float32(let value):
            try encode(.float32, value, into: &container)
        case .float64(let value):
            try encode(.float64, value, into: &container)
        case .decimal(let value):
            try encode(.decimal, value, into: &container)
        case .string(let value):
            try encode(.string, value, into: &container)
        case .bytes(let value):
            // Codable requires an independently owned collection here.
            try encode(.bytes, value.copyBytes(), into: &container)
        case .date(let value):
            try encode(.date, value, into: &container)
        case .time(let value):
            try encode(.time, value, into: &container)
        case .dateTime(let value):
            try encode(.dateTime, value, into: &container)
        case .timestamp(let value):
            try encode(.timestamp, value, into: &container)
        case .timeSpan(let value):
            try encode(.timeSpan, value, into: &container)
        case .calendarPeriod(let value):
            try encode(.calendarPeriod, value, into: &container)
        case .geographicPoint(let value):
            try encode(.geographicPoint, value, into: &container)
        case .geographicPosition(let value):
            try encode(.geographicPosition, value, into: &container)
        case .vector(let value):
            try encode(.vector, value, into: &container)
        case .uuid(let value):
            try encode(
                .uuid,
                EncodedUUID(high: value.high, low: value.low),
                into: &container
            )
        case .array(let values):
            try encode(.array, values, into: &container)
        case .object(let value):
            try encode(.object, value, into: &container)
        case .reference(let value):
            try encode(.reference, value, into: &container)
        case .rdfTerm(let value):
            try encode(.rdfTerm, value, into: &container)
        }
    }

    private func encode<Value: Encodable>(
        _ kind: EncodedValueKind,
        _ value: Value,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
    }
}
