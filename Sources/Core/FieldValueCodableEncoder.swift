import DatabaseTypes
import DatabaseTypesFoundation
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
            return .bytes(ByteString(retaining: scalar))
        case let scalar as Foundation.UUID:
            return .uuid(DatabaseTypes.UUID(scalar))
        case let scalar as Date:
            return .timestamp(try Timestamp(scalar))
        case let scalar as RDFTerm: return .rdfTerm(scalar)
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
        encodedValue = .object(FieldObject())
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
    private var entries: [(key: String, value: FieldValue)] = []
    private let commitObject: (FieldValue) -> Void

    init(commitObject: @escaping (FieldValue) -> Void) {
        self.commitObject = commitObject
    }

    func set(_ value: FieldValue, for key: some CodingKey) {
        if let index = entries.firstIndex(where: { $0.key == key.stringValue }) {
            entries[index].value = value
        } else {
            entries.append((key.stringValue, value))
        }
        let object: FieldObject
        do {
            object = try FieldObject(entries)
        } catch {
            preconditionFailure(
                "Keyed encoding state produced duplicate object keys"
            )
        }
        commitObject(.object(object))
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
