import DatabaseValue
import DatabaseValueCodable
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public protocol PersistableScalarDecodable: Sendable, Decodable {
    static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Self
}

extension Bool: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
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
        _ value: DatabaseValue,
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
        _ value: DatabaseValue,
        field: String
    ) throws -> Int8 {
        guard case .int64(let scalar) = value, let result = Int8(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int8")
        }
        return result
    }
}

extension Int16: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Int16 {
        guard case .int64(let scalar) = value, let result = Int16(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int16")
        }
        return result
    }
}

extension Int32: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Int32 {
        guard case .int64(let scalar) = value, let result = Int32(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an Int32")
        }
        return result
    }
}

extension Int64: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
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
        _ value: DatabaseValue,
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
        _ value: DatabaseValue,
        field: String
    ) throws -> UInt8 {
        guard case .uint64(let scalar) = value, let result = UInt8(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt8")
        }
        return result
    }
}

extension UInt16: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> UInt16 {
        guard case .uint64(let scalar) = value, let result = UInt16(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt16")
        }
        return result
    }
}

extension UInt32: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> UInt32 {
        guard case .uint64(let scalar) = value, let result = UInt32(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UInt32")
        }
        return result
    }
}

extension UInt64: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
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
        _ value: DatabaseValue,
        field: String
    ) throws -> Float {
        guard case .double(let scalar) = value, let result = Float(exactly: scalar) else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Float")
        }
        return result
    }
}

extension Double: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Double {
        guard case .double(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a Double")
        }
        return scalar
    }
}

extension String: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> String {
        guard case .string(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a String")
        }
        return scalar
    }
}

extension Data: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Data {
        guard case .bytes(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "bytes")
        }
        return Data(scalar)
    }
}

extension UUID: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> UUID {
        guard case .uuid(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "a UUID")
        }
        return UUID(uuid: (
            scalar[0], scalar[1], scalar[2], scalar[3],
            scalar[4], scalar[5], scalar[6], scalar[7],
            scalar[8], scalar[9], scalar[10], scalar[11],
            scalar[12], scalar[13], scalar[14], scalar[15]
        ))
    }
}

extension Date: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> Date {
        let seconds: Double
        switch value {
        case .timestamp(let timestamp):
            guard timestamp.nanoseconds < 1_000_000_000 else {
                throw PersistableDecodingError.invalidDate(field: field)
            }
            seconds = Double(timestamp.secondsSinceUnixEpoch)
                + Double(timestamp.nanoseconds) / 1_000_000_000
        case .date(let date):
            guard let days = databaseDaysSinceUnixEpoch(date) else {
                throw PersistableDecodingError.invalidDate(field: field)
            }
            seconds = Double(days * 86_400)
        default:
            throw PersistableDecodingError.invalidValue(field: field, expected: "a date or timestamp")
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

extension DatabaseRDFTerm: PersistableScalarDecodable {
    public static func decodePersistedScalar(
        _ value: DatabaseValue,
        field: String
    ) throws -> DatabaseRDFTerm {
        guard case .rdfTerm(let scalar) = value else {
            throw PersistableDecodingError.invalidValue(field: field, expected: "an RDF term")
        }
        return scalar
    }
}

private func databaseDaysSinceUnixEpoch(_ date: DatabaseDate) -> Int64? {
    let year = Int64(date.year)
    let month = Int64(date.month)
    let day = Int64(date.day)
    guard (1...12).contains(month),
          day >= 1,
          day <= databaseDaysInMonth(year: year, month: month) else {
        return nil
    }

    let adjustedYear = year - (month <= 2 ? 1 : 0)
    let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
    let yearOfEra = adjustedYear - era * 400
    let adjustedMonth = month + (month > 2 ? -3 : 9)
    let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

private func databaseDaysInMonth(year: Int64, month: Int64) -> Int64 {
    switch month {
    case 2:
        let leap = year.isMultiple(of: 4)
            && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        return leap ? 29 : 28
    case 4, 6, 9, 11:
        return 30
    default:
        return 31
    }
}
