import DatabaseTypes

/// A value that can be represented by the canonical database field model.
public protocol FieldValueEncodable: Sendable {
    /// The scalar schema category after Optional and Array containers are removed.
    static var fieldSchemaType: FieldSchemaType { get }

    /// Static enum catalog metadata. Non-enum values return `nil`.
    static func fieldEnumMetadata(named typeName: String) -> EnumMetadata?

    /// Produces the canonical field representation without type erasure.
    func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue
}

public extension FieldValueEncodable {
    static func fieldEnumMetadata(named typeName: String) -> EnumMetadata? {
        nil
    }
}

extension Bool: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .bool }
    public func encodeFieldValue() -> FieldValue { .bool(self) }
}

extension Int: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .int64 }
    public func encodeFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int8: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .int8 }
    public func encodeFieldValue() -> FieldValue { .int8(self) }
}

extension Int16: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .int16 }
    public func encodeFieldValue() -> FieldValue { .int16(self) }
}

extension Int32: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .int32 }
    public func encodeFieldValue() -> FieldValue { .int32(self) }
}

extension Int64: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .int64 }
    public func encodeFieldValue() -> FieldValue { .int64(self) }
}

extension UInt: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uint64 }
    public func encodeFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt8: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uint8 }
    public func encodeFieldValue() -> FieldValue { .uint8(self) }
}

extension UInt16: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uint16 }
    public func encodeFieldValue() -> FieldValue { .uint16(self) }
}

extension UInt32: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uint32 }
    public func encodeFieldValue() -> FieldValue { .uint32(self) }
}

extension UInt64: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uint64 }
    public func encodeFieldValue() -> FieldValue { .uint64(self) }
}

extension Float: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .float32 }
    public func encodeFieldValue() -> FieldValue { .float32(self) }
}

extension Double: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .float64 }
    public func encodeFieldValue() -> FieldValue { .float64(self) }
}

extension String: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .string }
    public func encodeFieldValue() -> FieldValue { .string(self) }
}

extension ExactDecimal: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .decimal }
    public func encodeFieldValue() -> FieldValue { .decimal(self) }
}

extension ByteString: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .bytes }
    public func encodeFieldValue() -> FieldValue { .bytes(self) }
}

extension CivilDate: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .date }
    public func encodeFieldValue() -> FieldValue { .date(self) }
}

extension CivilTime: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .time }
    public func encodeFieldValue() -> FieldValue { .time(self) }
}

extension CivilDateTime: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .dateTime }
    public func encodeFieldValue() -> FieldValue { .dateTime(self) }
}

extension Timestamp: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .timestamp }
    public func encodeFieldValue() -> FieldValue { .timestamp(self) }
}

extension TimeSpan: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .timeSpan }
    public func encodeFieldValue() -> FieldValue { .timeSpan(self) }
}

extension CalendarPeriod: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .calendarPeriod }
    public func encodeFieldValue() -> FieldValue { .calendarPeriod(self) }
}

extension GeographicPoint: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .geographicPoint }
    public func encodeFieldValue() -> FieldValue { .geographicPoint(self) }
}

extension GeographicPosition: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .geographicPosition }
    public func encodeFieldValue() -> FieldValue { .geographicPosition(self) }
}

extension DatabaseTypes.Vector: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .vector }
    public func encodeFieldValue() -> FieldValue { .vector(self) }
}

extension DatabaseTypes.UUID: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .uuid }
    public func encodeFieldValue() -> FieldValue { .uuid(self) }
}

extension FieldObject: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .object }
    public func encodeFieldValue() -> FieldValue { .object(self) }
}

extension EntityReference: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .reference }
    public func encodeFieldValue() -> FieldValue { .reference(self) }
}

extension RDFTerm: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .rdfTerm }
    public func encodeFieldValue() -> FieldValue { .rdfTerm(self) }
}

extension Array: FieldValueEncodable where Element: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType {
        Element.fieldSchemaType
    }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        var values: [FieldValue] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try element.encodeFieldValue())
        }
        return .array(values)
    }
}

extension Optional: FieldValueEncodable where Wrapped: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType {
        Wrapped.fieldSchemaType
    }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        switch self {
        case .some(let value):
            return try value.encodeFieldValue()
        case .none:
            return .null
        }
    }
}
