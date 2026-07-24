import DatabaseTypes
import DatabaseTypesFoundation
import DatabaseValue
import DatabaseValueCodable
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public protocol PersistableScalarDecodable: Sendable, Decodable {
    static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Self
}

extension Bool: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Bool {
        guard case .bool(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a boolean")
        }
        return scalar
    }
}

extension Int: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Int {
        guard case .int64(let scalar) = value, let result = Int(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int")
        }
        return result
    }
}

extension Int8: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Int8 {
        guard case .int8(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int8")
        }
        return scalar
    }
}

extension Int16: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Int16 {
        guard case .int16(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int16")
        }
        return scalar
    }
}

extension Int32: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Int32 {
        guard case .int32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int32")
        }
        return scalar
    }
}

extension Int64: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Int64 {
        guard case .int64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int64")
        }
        return scalar
    }
}

extension UInt: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> UInt {
        guard case .uint64(let scalar) = value, let result = UInt(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt")
        }
        return result
    }
}

extension UInt8: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> UInt8 {
        guard case .uint8(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt8")
        }
        return scalar
    }
}

extension UInt16: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> UInt16 {
        guard case .uint16(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt16")
        }
        return scalar
    }
}

extension UInt32: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> UInt32 {
        guard case .uint32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt32")
        }
        return scalar
    }
}

extension UInt64: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> UInt64 {
        guard case .uint64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt64")
        }
        return scalar
    }
}

extension Float: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Float {
        guard case .float32(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Float")
        }
        return scalar
    }
}

extension Double: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Double {
        guard case .float64(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Double")
        }
        return scalar
    }
}

extension String: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> String {
        guard case .string(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a String")
        }
        return scalar
    }
}

extension ExactDecimal: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> ExactDecimal {
        guard case .decimal(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an exact decimal")
        }
        return scalar
    }
}

extension ByteString: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> ByteString {
        guard case .bytes(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "bytes")
        }
        return scalar
    }
}

extension Data: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Data {
        guard case .bytes(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "bytes")
        }
        return Data(copying: scalar)
    }
}

extension FoundationUUID: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Self {
        guard case .uuid(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UUID")
        }
        return Self(scalar)
    }
}

extension DatabaseTypes.UUID: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> DatabaseTypes.UUID {
        guard case .uuid(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UUID")
        }
        return scalar
    }
}

extension CivilDate: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> CivilDate {
        guard case .date(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil date")
        }
        return scalar
    }
}

extension CivilTime: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> CivilTime {
        guard case .time(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil time")
        }
        return scalar
    }
}

extension CivilDateTime: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> CivilDateTime {
        guard case .dateTime(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a civil date-time")
        }
        return scalar
    }
}

extension Timestamp: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Timestamp {
        guard case .timestamp(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a timestamp")
        }
        return scalar
    }
}

extension Date: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> Date {
        guard case .timestamp(let timestamp) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a date or timestamp")
        }
        return Date(timestamp)
    }
}

extension TimeSpan: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> TimeSpan {
        guard case .timeSpan(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a time span")
        }
        return scalar
    }
}

extension CalendarPeriod: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> CalendarPeriod {
        guard case .calendarPeriod(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a calendar period")
        }
        return scalar
    }
}

extension GeographicPoint: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> GeographicPoint {
        guard case .geographicPoint(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a geographic point")
        }
        return scalar
    }
}

extension GeographicPosition: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> GeographicPosition {
        guard case .geographicPosition(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a geographic position")
        }
        return scalar
    }
}

extension DatabaseTypes.Vector: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> DatabaseTypes.Vector {
        guard case .vector(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a vector")
        }
        return scalar
    }
}

extension FieldObject: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> FieldObject {
        guard case .object(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an object")
        }
        return scalar
    }
}

extension EntityReference: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> EntityReference {
        guard case .reference(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an entity reference")
        }
        return scalar
    }
}

extension RDFTerm: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: FieldValue,
        field: String
    ) throws -> RDFTerm {
        guard case .rdfTerm(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an RDF term")
        }
        return scalar
    }
}
