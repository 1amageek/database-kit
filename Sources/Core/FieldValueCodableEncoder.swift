import DatabaseValue
import DatabaseValueCodable
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum FieldValueCodableEncoder {
    public static func encode(_ value: any Encodable) throws -> FieldValue {
        try DatabaseValueEncoding.encode(value)
    }
}

private enum DatabaseValueEncoding {
    static func encode(_ value: any Encodable) throws -> FieldValue {
        switch value {
        case let scalar as Bool: return .bool(scalar)
        case let scalar as Int: return .int64(Int64(scalar))
        case let scalar as Int8: return .int8(scalar)
        case let scalar as Int16: return .int16(scalar)
        case let scalar as Int32: return .int32(scalar)
        case let scalar as Int64: return .int64(scalar)
        case let scalar as UInt: return .uint64(UInt64(scalar))
        case let scalar as UInt8: return .uint8(scalar)
        case let scalar as UInt16: return .uint16(scalar)
        case let scalar as UInt32: return .uint32(scalar)
        case let scalar as UInt64: return .uint64(scalar)
        case let scalar as Float: return .float32(scalar)
        case let scalar as Double: return .float64(scalar)
        case let scalar as String: return .string(scalar)
        case let scalar as Data:
            return .bytes(
                DatabaseBytes(
                    retaining: RetainedDataByteOwner(data: scalar)
                )
            )
        case let scalar as UUID: return .uuid(databaseUUID(scalar))
        case let scalar as Date: return .timestamp(try databaseTimestamp(scalar))
        case let scalar as DatabaseRDFTerm: return .rdfTerm(scalar)
        default:
            let encoder = DatabaseValueEncoder()
            try value.encode(to: encoder)
            guard let encoded = encoder.encodedValue else {
                throw EncodingError.invalidValue(
                    value,
                    .init(codingPath: [], debugDescription: "Value produced no encoded representation")
                )
            }
            return encoded
        }
    }

    private static func databaseUUID(_ value: UUID) -> DatabaseUUID {
        let bytes = value.uuid
        let values = [
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7,
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15,
        ]
        let high = values[..<8].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let low = values[8...].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return DatabaseUUID(high: high, low: low)
    }

    private static func databaseTimestamp(_ value: Date) throws -> DatabaseTimestamp {
        let interval = value.timeIntervalSince1970
        let integral = interval.rounded(.down)
        guard let seconds = Int64(exactly: integral) else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: [], debugDescription: "Date seconds exceed Int64")
            )
        }
        let nanoseconds = ((interval - integral) * 1_000_000_000).rounded()
        guard nanoseconds >= 0, nanoseconds < 1_000_000_000 else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: [], debugDescription: "Date nanoseconds are invalid")
            )
        }
        return DatabaseTimestamp(
            secondsSinceUnixEpoch: seconds,
            nanoseconds: UInt32(nanoseconds)
        )
    }
}

private final class DatabaseValueEncoder: Encoder {
    var encodedValue: FieldValue? {
        didSet {
            if let encodedValue { commitValue(encodedValue) }
        }
    }
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]
    private let commitValue: (FieldValue) -> Void

    init(
        codingPath: [CodingKey] = [],
        commitValue: @escaping (FieldValue) -> Void = { _ in }
    ) {
        self.codingPath = codingPath
        self.commitValue = commitValue
    }

    func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> {
        let objectState = DatabaseObjectEncodingState { [weak self] value in
            self?.encodedValue = value
        }
        encodedValue = .object([])
        return KeyedEncodingContainer(
            DatabaseValueKeyedEncodingContainer<Key>(
                objectState: objectState,
                codingPath: codingPath
            )
        )
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let arrayState = DatabaseArrayEncodingState { [weak self] value in
            self?.encodedValue = value
        }
        encodedValue = .array([])
        return DatabaseValueUnkeyedEncodingContainer(
            arrayState: arrayState,
            codingPath: codingPath
        )
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        DatabaseValueSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }
}

private final class DatabaseObjectEncodingState {
    private var entries: [(name: String, number: UInt32, value: FieldValue)] = []
    private let commitObject: (FieldValue) -> Void

    init(commitObject: @escaping (FieldValue) -> Void) {
        self.commitObject = commitObject
    }

    func set(_ value: FieldValue, for key: some CodingKey) {
        if let index = entries.firstIndex(where: { $0.name == key.stringValue }) {
            entries[index].value = value
        } else {
            let candidate = key.intValue.flatMap(UInt32.init(exactly:))
            var number = candidate ?? UInt32(entries.count + 1)
            if number == 0 || entries.contains(where: { $0.number == number }) {
                number = 1
                while entries.contains(where: { $0.number == number }) {
                    number += 1
                }
            }
            entries.append((key.stringValue, number, value))
        }
        commitObject(
            .object(
                entries.map {
                    DatabaseObjectField(number: $0.number, name: $0.name, value: $0.value)
                }
            )
        )
    }
}

private struct DatabaseValueKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let objectState: DatabaseObjectEncodingState
    let codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws { objectState.set(.null, for: key) }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        objectState.set(try DatabaseValueEncoding.encode(value), for: key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        childEncoder(for: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        childEncoder(for: key).unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder {
        DatabaseValueEncoder(codingPath: codingPath)
    }

    mutating func superEncoder(forKey key: Key) -> Encoder { childEncoder(for: key) }

    private func childEncoder(for key: Key) -> DatabaseValueEncoder {
        DatabaseValueEncoder(codingPath: codingPath + [key]) { value in
            objectState.set(value, for: key)
        }
    }
}

private final class DatabaseArrayEncodingState {
    private var values: [FieldValue] = []
    private let commitArray: (FieldValue) -> Void

    init(commitArray: @escaping (FieldValue) -> Void) {
        self.commitArray = commitArray
    }

    var count: Int { values.count }

    func append(_ value: FieldValue) {
        values.append(value)
        commitArray(.array(values))
    }

    func replace(at index: Int, with value: FieldValue) {
        values[index] = value
        commitArray(.array(values))
    }
}

private struct DatabaseValueUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let arrayState: DatabaseArrayEncodingState
    let codingPath: [CodingKey]
    var count: Int { arrayState.count }

    mutating func encodeNil() throws { arrayState.append(.null) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        arrayState.append(try DatabaseValueEncoding.encode(value))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        childEncoder().container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        childEncoder().unkeyedContainer()
    }

    mutating func superEncoder() -> Encoder { childEncoder() }

    private func childEncoder() -> DatabaseValueEncoder {
        let index = arrayState.count
        arrayState.append(.null)
        return DatabaseValueEncoder(
            codingPath: codingPath + [DatabaseValueEncodingIndexKey(intValue: index)]
        ) { value in
            arrayState.replace(at: index, with: value)
        }
    }
}

private struct DatabaseValueSingleValueEncodingContainer: SingleValueEncodingContainer {
    let encoder: DatabaseValueEncoder
    let codingPath: [CodingKey]

    func encodeNil() throws { encoder.encodedValue = .null }

    func encode<T: Encodable>(_ value: T) throws {
        encoder.encodedValue = try DatabaseValueEncoding.encode(value)
    }
}

private struct DatabaseValueEncodingIndexKey: CodingKey {
    let intValue: Int?
    let stringValue: String

    init(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "Index \(intValue)"
    }

    init?(stringValue: String) { return nil }
}
