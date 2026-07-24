import DatabaseTypes
import DatabaseTypesFoundation
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum FieldValueCodableDecoder {
    public static func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: FieldValue
    ) throws -> Value {
        try FieldValueDecoding.decode(type, from: value, codingPath: [])
    }
}

private enum FieldValueDecoding {
    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from value: FieldValue,
        codingPath: [CodingKey]
    ) throws -> Value {
        if type == Data.self, case .bytes(let bytes) = value {
            return try cast(Data(copying: bytes), to: type, codingPath: codingPath)
        }
        if type == FoundationUUID.self, case .uuid(let uuid) = value {
            let decoded = FoundationUUID(uuid)
            return try cast(decoded, to: type, codingPath: codingPath)
        }
        if type == Date.self {
            let decoded = try decodeDate(value, codingPath: codingPath)
            return try cast(decoded, to: type, codingPath: codingPath)
        }
        if type == RDFTerm.self, case .rdfTerm(let term) = value {
            return try cast(term, to: type, codingPath: codingPath)
        }
        return try Value(from: FieldValueDecoder(value: value, codingPath: codingPath))
    }

    static func typeMismatch<Value>(
        _ type: Value.Type,
        value: FieldValue,
        codingPath: [CodingKey]
    ) -> DecodingError {
        .typeMismatch(
            type,
            .init(
                codingPath: codingPath,
                debugDescription: "Cannot decode \(type) from \(value)"
            )
        )
    }

    private static func cast<Value, Result>(
        _ value: Value,
        to type: Result.Type,
        codingPath: [CodingKey]
    ) throws -> Result {
        guard let result = value as? Result else {
            throw DecodingError.typeMismatch(
                type,
                .init(codingPath: codingPath, debugDescription: "Invalid decoded value type")
            )
        }
        return result
    }

    private static func decodeDate(
        _ value: FieldValue,
        codingPath: [CodingKey]
    ) throws -> Date {
        switch value {
        case .timestamp(let timestamp):
            return Date(timestamp)
        case .date(let date):
            guard let days = daysSinceUnixEpoch(date) else {
                throw typeMismatch(Date.self, value: value, codingPath: codingPath)
            }
            return Date(timeIntervalSince1970: Double(days * 86_400))
        default:
            throw typeMismatch(Date.self, value: value, codingPath: codingPath)
        }
    }

    private static func daysSinceUnixEpoch(_ date: CivilDate) -> Int64? {
        let year = Int64(date.year)
        let month = Int64(date.month)
        let day = Int64(date.day)
        guard (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month) else {
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

    private static func daysInMonth(year: Int64, month: Int64) -> Int64 {
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
}

private final class FieldValueDecoder: Decoder {
    let value: FieldValue
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]

    init(value: FieldValue, codingPath: [CodingKey]) {
        self.value = value
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let fields) = value else {
            throw FieldValueDecoding.typeMismatch(
                [String: FieldValue].self,
                value: value,
                codingPath: codingPath
            )
        }
        return KeyedDecodingContainer(
            try FieldValueKeyedDecodingContainer<Key>(
                fields: fields,
                codingPath: codingPath
            )
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let values) = value else {
            throw FieldValueDecoding.typeMismatch(
                [FieldValue].self,
                value: value,
                codingPath: codingPath
            )
        }
        return FieldValueUnkeyedDecodingContainer(
            values: values,
            codingPath: codingPath
        )
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        FieldValueSingleValueDecodingContainer(value: value, codingPath: codingPath)
    }
}

private struct FieldValueKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let codingPath: [CodingKey]
    let allKeys: [Key]
    private let values: [String: FieldValue]

    init(fields: FieldObject, codingPath: [CodingKey]) throws {
        var mapped: [String: FieldValue] = [:]
        var keys: [Key] = []
        for field in fields.fields {
            guard mapped.updateValue(field.value, forKey: field.key) == nil else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: codingPath, debugDescription: "Duplicate object field '\(field.key)'")
                )
            }
            if let key = Key(stringValue: field.key) {
                keys.append(key)
            }
        }
        self.values = mapped
        self.allKeys = keys
        self.codingPath = codingPath
    }

    func contains(_ key: Key) -> Bool { values[key.stringValue] != nil }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let value = values[key.stringValue] else { return true }
        if case .null = value { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        guard let value = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "Missing field '\(key.stringValue)'")
            )
        }
        return try FieldValueDecoding.decode(
            type,
            from: value,
            codingPath: codingPath + [key]
        )
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try decoder(for: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try decoder(for: key).unkeyedContainer()
    }

    func superDecoder() throws -> Decoder {
        FieldValueDecoder(value: .object(FieldObject()), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> Decoder { try decoder(for: key) }

    private func decoder(for key: Key) throws -> FieldValueDecoder {
        guard let value = values[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "Missing field '\(key.stringValue)'")
            )
        }
        return FieldValueDecoder(value: value, codingPath: codingPath + [key])
    }
}

private struct FieldValueUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    let values: [FieldValue]
    let codingPath: [CodingKey]
    var currentIndex = 0
    var count: Int? { values.count }
    var isAtEnd: Bool { currentIndex >= values.count }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw endError() }
        if case .null = values[currentIndex] {
            currentIndex += 1
            return true
        }
        return false
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        guard !isAtEnd else { throw endError() }
        let index = currentIndex
        currentIndex += 1
        return try FieldValueDecoding.decode(
            type,
            from: values[index],
            codingPath: codingPath + [FieldValueDecodingIndexKey(intValue: index)]
        )
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try nextDecoder().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        try nextDecoder().unkeyedContainer()
    }

    mutating func superDecoder() throws -> Decoder { try nextDecoder() }

    private mutating func nextDecoder() throws -> FieldValueDecoder {
        guard !isAtEnd else { throw endError() }
        let index = currentIndex
        currentIndex += 1
        return FieldValueDecoder(
            value: values[index],
            codingPath: codingPath + [FieldValueDecodingIndexKey(intValue: index)]
        )
    }

    private func endError() -> DecodingError {
        .valueNotFound(
            FieldValue.self,
            .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end")
        )
    }
}

private struct FieldValueSingleValueDecodingContainer: SingleValueDecodingContainer {
    let value: FieldValue
    let codingPath: [CodingKey]

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: String.Type) throws -> String {
        guard case .string(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Double.Type) throws -> Double {
        guard case .float64(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Float.Type) throws -> Float {
        guard case .float32(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Int.Type) throws -> Int {
        guard case .int64(let scalar) = value, let result = Int(exactly: scalar) else {
            throw mismatch(type)
        }
        return result
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        guard case .int8(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        guard case .int16(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        guard case .int32(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        guard case .int64(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        guard case .uint64(let scalar) = value, let result = UInt(exactly: scalar) else {
            throw mismatch(type)
        }
        return result
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        guard case .uint8(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        guard case .uint16(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        guard case .uint32(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        guard case .uint64(let scalar) = value else { throw mismatch(type) }
        return scalar
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try FieldValueDecoding.decode(type, from: value, codingPath: codingPath)
    }

    private func mismatch<T>(_ type: T.Type) -> DecodingError {
        FieldValueDecoding.typeMismatch(type, value: value, codingPath: codingPath)
    }
}

private struct FieldValueDecodingIndexKey: CodingKey {
    let intValue: Int?
    let stringValue: String

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "Index \(intValue)"
    }

    init?(stringValue: String) { return nil }
}
