#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseTypes
import DatabaseTypesFoundation

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
                try PersistableField(
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
        case .int8:
            value = (raw as? Int8).map(FieldValue.int8)
        case .int16:
            value = (raw as? Int16).map(FieldValue.int16)
        case .int32:
            value = (raw as? Int32).map(FieldValue.int32)
        case .int64:
            value = (raw as? Int64).map(FieldValue.int64)
        case .uint8:
            value = (raw as? UInt8).map(FieldValue.uint8)
        case .uint16:
            value = (raw as? UInt16).map(FieldValue.uint16)
        case .uint32:
            value = (raw as? UInt32).map(FieldValue.uint32)
        case .uint64:
            value = (raw as? UInt64).map(FieldValue.uint64)
        case .float32:
            value = (raw as? Float).map(FieldValue.float32)
        case .float64:
            value = (raw as? Double).map(FieldValue.float64)
        case .decimal:
            value = (raw as? ExactDecimal).map(FieldValue.decimal)
        case .string:
            value = (raw as? String).map(FieldValue.string)
        case .bytes:
            if let scalar = raw as? ByteString {
                value = .bytes(scalar)
            } else if let scalar = raw as? Data {
                value = .bytes(ByteString(retaining: scalar))
            } else if let scalar = raw as? [UInt8] {
                value = .bytes(ByteString(scalar))
            } else {
                value = nil
            }
        case .date:
            value = (raw as? CivilDate).map(FieldValue.date)
        case .time:
            value = (raw as? CivilTime).map(FieldValue.time)
        case .dateTime:
            value = (raw as? CivilDateTime).map(FieldValue.dateTime)
        case .timestamp:
            if let scalar = raw as? Timestamp {
                value = .timestamp(scalar)
            } else if let scalar = raw as? Date {
                value = .timestamp(try Timestamp(scalar))
            } else {
                value = nil
            }
        case .timeSpan:
            value = (raw as? TimeSpan).map(FieldValue.timeSpan)
        case .calendarPeriod:
            value = (raw as? CalendarPeriod).map(FieldValue.calendarPeriod)
        case .geographicPoint:
            value = (raw as? GeographicPoint).map(FieldValue.geographicPoint)
        case .geographicPosition:
            value = (raw as? GeographicPosition).map(FieldValue.geographicPosition)
        case .vector:
            value = (raw as? DatabaseTypes.Vector).map(FieldValue.vector)
        case .uuid:
            if let scalar = raw as? FoundationUUID {
                value = .uuid(DatabaseTypes.UUID(scalar))
            } else if let scalar = raw as? DatabaseTypes.UUID {
                value = .uuid(scalar)
            } else {
                value = nil
            }
        case .object:
            value = (raw as? FieldObject).map(FieldValue.object)
        case .rdfTerm:
            value = (raw as? RDFTerm).map(FieldValue.rdfTerm)
        case .reference:
            if let scalar = raw as? EntityReference {
                value = .reference(scalar)
            } else if let scalar = raw as? any PersistableReferenceValue {
                value = .reference(scalar.persistableIdentity)
            } else {
                value = nil
            }
        case .enum:
            if let representable = raw as? any RawRepresentable {
                value = enumValue(representable.rawValue)
            } else {
                value = enumValue(raw)
            }
        case .nested:
            if let nested = raw as? any Persistable {
                value = .object(try fieldObject(from: encode(nested)))
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

    private static func fieldObject(
        from fields: consuming [PersistableField]
    ) throws -> FieldObject {
        try FieldObject(
            fields.map {
                (key: $0.name, value: $0.value)
            }
        )
    }
}
