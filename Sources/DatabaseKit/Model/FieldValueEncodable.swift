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

extension Bool: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .bool }
    public var fieldValue: FieldValue { .bool(self) }
}

extension Int: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .int64 }
    public var fieldValue: FieldValue { .int64(Int64(self)) }
}

extension Int8: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .int8 }
    public var fieldValue: FieldValue { .int8(self) }
}

extension Int16: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .int16 }
    public var fieldValue: FieldValue { .int16(self) }
}

extension Int32: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .int32 }
    public var fieldValue: FieldValue { .int32(self) }
}

extension Int64: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .int64 }
    public var fieldValue: FieldValue { .int64(self) }
}

extension UInt: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uint64 }
    public var fieldValue: FieldValue { .uint64(UInt64(self)) }
}

extension UInt8: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uint8 }
    public var fieldValue: FieldValue { .uint8(self) }
}

extension UInt16: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uint16 }
    public var fieldValue: FieldValue { .uint16(self) }
}

extension UInt32: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uint32 }
    public var fieldValue: FieldValue { .uint32(self) }
}

extension UInt64: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uint64 }
    public var fieldValue: FieldValue { .uint64(self) }
}

extension Float: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .float32 }
    public var fieldValue: FieldValue { .float32(self) }
}

extension Double: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .float64 }
    public var fieldValue: FieldValue { .float64(self) }
}

extension String: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .string }
    public var fieldValue: FieldValue { .string(self) }
}

extension ExactDecimal: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .decimal }
    public var fieldValue: FieldValue { .decimal(self) }
}

extension ByteString: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .bytes }
    public var fieldValue: FieldValue { .bytes(self) }
}

extension CivilDate: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .date }
    public var fieldValue: FieldValue { .date(self) }
}

extension CivilTime: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .time }
    public var fieldValue: FieldValue { .time(self) }
}

extension CivilDateTime: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .dateTime }
    public var fieldValue: FieldValue { .dateTime(self) }
}

extension Timestamp: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .timestamp }
    public var fieldValue: FieldValue { .timestamp(self) }
}

extension TimeSpan: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .timeSpan }
    public var fieldValue: FieldValue { .timeSpan(self) }
}

extension CalendarPeriod: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .calendarPeriod }
    public var fieldValue: FieldValue { .calendarPeriod(self) }
}

extension GeographicPoint: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .geographicPoint }
    public var fieldValue: FieldValue { .geographicPoint(self) }
}

extension GeographicPosition: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .geographicPosition }
    public var fieldValue: FieldValue { .geographicPosition(self) }
}

extension DatabaseTypes.Vector: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .vector }
    public var fieldValue: FieldValue { .vector(self) }
}

extension DatabaseTypes.UUID: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .uuid }
    public var fieldValue: FieldValue { .uuid(self) }
}

extension FieldObject: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .object }
    public var fieldValue: FieldValue { .object(self) }
}

extension EntityReference: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .reference }
    public var fieldValue: FieldValue { .reference(self) }
}

extension RDFTerm: FieldValueEncodable, FieldValueRepresentable {
    public static var fieldSchemaType: FieldSchemaType { .rdfTerm }
    public var fieldValue: FieldValue { .rdfTerm(self) }
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

extension Array: FieldValueRepresentable where Element: FieldValueRepresentable {
    public var fieldValue: FieldValue {
        var values: [FieldValue] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(element.fieldValue)
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

extension Optional: FieldValueRepresentable where Wrapped: FieldValueRepresentable {
    public var fieldValue: FieldValue {
        switch self {
        case .some(let value):
            return value.fieldValue
        case .none:
            return .null
        }
    }
}
