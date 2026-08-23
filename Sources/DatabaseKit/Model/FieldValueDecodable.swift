import DatabaseTypes

public protocol FieldValueDecodable: Sendable {
    static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Self
}

extension Bool: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Bool {
        guard case .bool(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a boolean")
        }
        return scalar
    }
}

extension Int: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Int {
        guard case .int64(let scalar) = value, let result = Int(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int")
        }
        return result
    }
}

extension Int8: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Int8 {
        guard case .int8(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int8")
        }
        return scalar
    }
}

extension Int16: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Int16 {
        guard case .int16(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int16")
        }
        return scalar
    }
}

extension Int32: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Int32 {
        guard case .int32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int32")
        }
        return scalar
    }
}

extension Int64: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Int64 {
        guard case .int64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int64")
        }
        return scalar
    }
}

extension UInt: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> UInt {
        guard case .uint64(let scalar) = value, let result = UInt(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt")
        }
        return result
    }
}

extension UInt8: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> UInt8 {
        guard case .uint8(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt8")
        }
        return scalar
    }
}

extension UInt16: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> UInt16 {
        guard case .uint16(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt16")
        }
        return scalar
    }
}

extension UInt32: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> UInt32 {
        guard case .uint32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt32")
        }
        return scalar
    }
}

extension UInt64: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> UInt64 {
        guard case .uint64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt64")
        }
        return scalar
    }
}

extension Float: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Float {
        guard case .float32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Float")
        }
        return scalar
    }
}

extension Double: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Double {
        guard case .float64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Double")
        }
        return scalar
    }
}

extension String: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> String {
        guard case .string(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a String")
        }
        return scalar
    }
}

extension ExactDecimal: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> ExactDecimal {
        guard case .decimal(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an exact decimal")
        }
        return scalar
    }
}

extension ByteString: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> ByteString {
        guard case .bytes(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "bytes")
        }
        return scalar
    }
}

extension DatabaseTypes.UUID: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> DatabaseTypes.UUID {
        guard case .uuid(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UUID")
        }
        return scalar
    }
}

extension CivilDate: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> CivilDate {
        guard case .date(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil date")
        }
        return scalar
    }
}

extension CivilTime: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> CivilTime {
        guard case .time(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil time")
        }
        return scalar
    }
}

extension CivilDateTime: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> CivilDateTime {
        guard case .dateTime(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil date-time")
        }
        return scalar
    }
}

extension Timestamp: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Timestamp {
        guard case .timestamp(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a timestamp")
        }
        return scalar
    }
}

extension TimeSpan: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> TimeSpan {
        guard case .timeSpan(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a time span")
        }
        return scalar
    }
}

extension CalendarPeriod: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> CalendarPeriod {
        guard case .calendarPeriod(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a calendar period")
        }
        return scalar
    }
}

extension GeographicPoint: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> GeographicPoint {
        guard case .geographicPoint(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a geographic point")
        }
        return scalar
    }
}

extension GeographicPosition: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> GeographicPosition {
        guard case .geographicPosition(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a geographic position")
        }
        return scalar
    }
}

extension DatabaseTypes.Vector: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> DatabaseTypes.Vector {
        guard case .vector(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a vector")
        }
        return scalar
    }
}

extension FieldObject: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> FieldObject {
        guard case .object(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an object")
        }
        return scalar
    }
}

extension EntityReference: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> EntityReference {
        guard case .reference(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an entity reference")
        }
        return scalar
    }
}

extension RDFTerm: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> RDFTerm {
        guard case .rdfTerm(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an RDF term")
        }
        return scalar
    }
}
