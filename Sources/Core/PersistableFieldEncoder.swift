#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseValue

public enum PersistableFieldEncoder {
    public static func encode(
        _ model: any Persistable
    ) throws -> [PersistableField] {
        let modelType = type(of: model)
        var seenNumbers = Set<Int>()
        var seenNames = Set<String>()
        var fields: [PersistableField] = []
        fields.reserveCapacity(modelType.fieldSchemas.count)

        for schema in modelType.fieldSchemas.sorted(by: { $0.fieldNumber < $1.fieldNumber }) {
            guard schema.fieldNumber > 0,
                  let number = UInt32(exactly: schema.fieldNumber) else {
                throw PersistableEncodingError.invalidSchema(
                    entity: modelType.persistableType,
                    reason: "field '\(schema.name)' has invalid number \(schema.fieldNumber)"
                )
            }
            guard seenNumbers.insert(schema.fieldNumber).inserted else {
                throw PersistableEncodingError.invalidSchema(
                    entity: modelType.persistableType,
                    reason: "field number \(schema.fieldNumber) is duplicated"
                )
            }
            guard seenNames.insert(schema.name).inserted else {
                throw PersistableEncodingError.invalidSchema(
                    entity: modelType.persistableType,
                    reason: "field name '\(schema.name)' is duplicated"
                )
            }
            fields.append(
                PersistableField(
                    number: number,
                    name: schema.name,
                    value: try encodeValue(
                        model[dynamicMember: schema.name],
                        schema: schema,
                        entity: modelType.persistableType
                    )
                )
            )
        }
        return fields
    }

    public static func encodeValue(
        _ raw: (any Sendable)?,
        schema: FieldSchema,
        entity: String
    ) throws -> FieldValue {
        guard let raw else { return .null }
        if schema.isArray {
            let mirror = Mirror(reflecting: raw)
            guard mirror.displayStyle == .collection else {
                throw PersistableEncodingError.fieldNotRepresentable(
                    entity: entity,
                    field: schema.name
                )
            }
            return .array(
                try mirror.children.map {
                    try encodeScalar(
                        $0.value,
                        type: schema.type,
                        entity: entity,
                        field: schema.name
                    )
                }
            )
        }
        return try encodeScalar(
            raw,
            type: schema.type,
            entity: entity,
            field: schema.name
        )
    }

    private static func encodeScalar(
        _ raw: Any,
        type: FieldSchemaType,
        entity: String,
        field: String
    ) throws -> FieldValue {
        let value: FieldValue?
        switch type {
        case .bool:
            value = (raw as? Bool).map(FieldValue.bool)
        case .int, .int8, .int16, .int32, .int64:
            value = signedInteger(raw).map(FieldValue.int64)
        case .uint, .uint8, .uint16, .uint32, .uint64:
            value = unsignedInteger(raw).map(FieldValue.uint64)
        case .double, .float:
            if let scalar = raw as? Double {
                value = .double(scalar)
            } else if let scalar = raw as? Float {
                value = .double(Double(scalar))
            } else {
                value = nil
            }
        case .string:
            value = (raw as? String).map(FieldValue.string)
        case .uuid:
            if let scalar = raw as? UUID {
                value = databaseUUID(scalar).map(FieldValue.uuid)
            } else {
                value = nil
            }
        case .data:
            if let scalar = raw as? Data {
                value = .bytes(
                    DatabaseBytes(
                        retaining: RetainedDataByteOwner(data: scalar)
                    )
                )
            } else if let scalar = raw as? [UInt8] {
                value = .bytes(DatabaseBytes(scalar))
            } else {
                value = nil
            }
        case .rdfTerm:
            value = (raw as? DatabaseRDFTerm).map(FieldValue.rdfTerm)
        case .reference:
            value = (raw as? any PersistableReferenceValue).map {
                .reference($0.persistableIdentity)
            }
        case .date:
            value = (raw as? Date).flatMap { databaseTimestamp($0).map(FieldValue.timestamp) }
        case .enum:
            if let representable = raw as? any RawRepresentable {
                value = enumValue(representable.rawValue)
            } else {
                value = enumValue(raw)
            }
        case .nested:
            if let nested = raw as? any Persistable {
                value = .object(try encode(nested))
            } else if let nested = raw as? any Encodable {
                let encoded = try FieldValueCodableEncoder.encode(nested)
                if case .object = encoded {
                    value = encoded
                } else {
                    value = nil
                }
            } else {
                value = nil
            }
        }

        guard let value else {
            throw PersistableEncodingError.fieldNotRepresentable(
                entity: entity,
                field: field
            )
        }
        return value
    }

    private static func signedInteger(_ raw: Any) -> Int64? {
        switch raw {
        case let value as Int: return Int64(value)
        case let value as Int8: return Int64(value)
        case let value as Int16: return Int64(value)
        case let value as Int32: return Int64(value)
        case let value as Int64: return value
        default: return nil
        }
    }

    private static func unsignedInteger(_ raw: Any) -> UInt64? {
        switch raw {
        case let value as UInt: return UInt64(value)
        case let value as UInt8: return UInt64(value)
        case let value as UInt16: return UInt64(value)
        case let value as UInt32: return UInt64(value)
        case let value as UInt64: return value
        default: return nil
        }
    }

    private static func enumValue(_ raw: Any) -> FieldValue? {
        if let value = raw as? String { return .string(value) }
        if let value = signedInteger(raw) { return .int64(value) }
        if let value = unsignedInteger(raw) { return .uint64(value) }
        return nil
    }

    private static func databaseTimestamp(_ value: Date) -> DatabaseTimestamp? {
        let interval = value.timeIntervalSince1970
        let integral = interval.rounded(.down)
        guard let seconds = Int64(exactly: integral) else { return nil }
        let fractional = interval - integral
        let nanoseconds = (fractional * 1_000_000_000).rounded()
        guard nanoseconds >= 0, nanoseconds < 1_000_000_000 else { return nil }
        return DatabaseTimestamp(
            secondsSinceUnixEpoch: seconds,
            nanoseconds: UInt32(nanoseconds)
        )
    }

    private static func databaseUUID(_ value: UUID) -> DatabaseUUID? {
        var uuid = value.uuid
        return withUnsafeBytes(of: &uuid) { bytes in
            DatabaseUUID(bytes: bytes)
        }
    }
}
