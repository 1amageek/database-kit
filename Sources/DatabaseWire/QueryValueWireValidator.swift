import DatabaseKit
import DatabaseTypes

/// Validates lazy cells in place without building primitive or JSONB trees.
enum QueryValueWireValidator {
    static func validate(from reader: inout DatabaseWireReader, type: QueryColumnType? = nil,
                         isNullable: Bool = true) throws(DatabaseWireError) {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        let tag = try reader.readUInt8()
        if tag == 4 {
            try reader.withNestedValue { reader throws(DatabaseWireError) in
                let shape = try QueryValueWireCodec.decodeArrayShape(from: &reader)
                if let type, type != .sql(.array(shape.type)) { throw .invalidQueryValue(.incompatibleType) }
                for index in 0..<shape.count {
                    do throws(DatabaseWireError) {
                        let elementTag = try reader.readUInt8()
                        try validateScalar(tag: elementTag, from: &reader, type: .sql(shape.type), isNullable: true)
                    } catch .invalidQueryValue(.incompatibleType) {
                        throw .invalidQueryValue(.elementTypeMismatch(index: UInt64(index)))
                    } catch let error { throw error }
                }
            }
        } else { try validateScalar(tag: tag, from: &reader, type: type, isNullable: isNullable) }
    }

    private static func validateScalar(tag: UInt8, from reader: inout DatabaseWireReader, type: QueryColumnType?,
                                      isNullable: Bool) throws(DatabaseWireError) {
        if let type, !QueryValueValidator.accepts(.primitive(.null), type: type) {
            throw .invalidQueryValue(.incompatibleType)
        }
        switch tag {
        case 0:
            try validatePrimitive(from: &reader, type: type, isNullable: isNullable)
        case 3:
            if let type, type != .sql(.jsonb) { throw .invalidQueryValue(.incompatibleType) }
            try QueryJSONBWireCodec.validate(from: &reader)
        case 1, 2, 5:
            try reader.withNestedValue { reader throws(DatabaseWireError) in
                switch tag {
                case 1:
                    let value = try QueryValueWireCodec.decodeNumeric(from: &reader)
                    if let type, !QueryValueValidator.accepts(.numeric(value), type: type) {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                case 2:
                    if let type, type != .sql(.json) { throw .invalidQueryValue(.incompatibleType) }
                    let json = try QueryValueWireCodec.decodeJSON(from: &reader)
                    try reader.registerQueryJSONFootprint(try QueryValueWireCodec.jsonFootprint(json))
                case 5:
                    if let type, type != .sql(.interval) { throw .invalidQueryValue(.incompatibleType) }
                    _ = try QueryValueWireCodec.decodeInterval(from: &reader)
                default: throw .invalidQueryIRWireState
                }
            }
        case 4:
            throw .invalidQueryValue(.incompatibleType)
        default: throw .invalidValueTag(tag)
        }
    }

    private static func validatePrimitive(from reader: inout DatabaseWireReader, type: QueryColumnType?,
                                          isNullable: Bool) throws(DatabaseWireError) {
        if let type, case .primitive(let kind, true) = type {
            var probe = reader
            let tag = try probe.readUInt8()
            if tag != 0 {
                guard tag == 25 else { try rejectIncompatiblePrimitive(from: reader) }
                try reader.withNestedValue { reader throws(DatabaseWireError) in
                    _ = try reader.readUInt8()
                    let count = try reader.readCount()
                    for _ in 0..<count {
                        try validatePrimitiveScalar(from: &reader, type: .primitive(kind), isNullable: true)
                    }
                }
                return
            }
        }
        try validatePrimitiveScalar(from: &reader, type: type, isNullable: isNullable)
    }

    private static func validatePrimitiveScalar(from reader: inout DatabaseWireReader, type: QueryColumnType?,
                                                isNullable: Bool) throws(DatabaseWireError) {
        var probe = reader
        let tag = try probe.readUInt8()
        if tag == 0 {
            guard isNullable else { throw .invalidQueryValue(.incompatibleType) }
        } else if let type {
            switch type {
            case .primitive(let kind, _):
                guard primitiveTag(tag, matches: kind) else { try rejectIncompatiblePrimitive(from: reader) }
            case .sql(let sql):
                guard sqlTag(tag, matches: sql) else { try rejectIncompatiblePrimitive(from: reader) }
                if tag == 10 || tag == 11 || tag == 12 {
                    var scalarReader = reader
                    let value = try FieldValueWireCodec.decodeValue(from: &scalarReader)
                    guard QueryValueValidator.accepts(.primitive(value), type: type) else {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                }
            }
        }
        try FieldValueWireValidator.validateValue(from: &reader)
    }

    private static func rejectIncompatiblePrimitive(from reader: DatabaseWireReader) throws(DatabaseWireError) -> Never {
        // Valid compatible payloads traverse once; mismatches consult the grammar owner.
        var probe = reader
        try FieldValueWireValidator.validateValue(from: &probe)
        throw .invalidQueryValue(.incompatibleType)
    }

    private static func primitiveTag(_ tag: UInt8, matches kind: FieldSchemaType) -> Bool {
        switch kind {
        case .bool: return tag == 1
        case .int8: return tag == 2
        case .int16: return tag == 3
        case .int32: return tag == 4
        case .int64: return tag == 5
        case .uint8: return tag == 6
        case .uint16: return tag == 7
        case .uint32: return tag == 8
        case .uint64: return tag == 9
        case .float32: return tag == 10
        case .float64: return tag == 11
        case .decimal: return tag == 12
        case .string: return tag == 13
        case .bytes: return tag == 14
        case .date: return tag == 15
        case .time: return tag == 16
        case .dateTime: return tag == 17
        case .timestamp: return tag == 18
        case .timeSpan: return tag == 19
        case .calendarPeriod: return tag == 20
        case .geographicPoint: return tag == 21
        case .geographicPosition: return tag == 22
        case .vector: return tag == 23
        case .uuid: return tag == 24
        case .object, .nested: return tag == 26
        case .reference: return tag == 27
        case .rdfTerm: return tag == 28
        case .enum: return tag == 13 || tag == 5
        }
    }

    private static func sqlTag(_ tag: UInt8, matches type: DataType) -> Bool {
        switch type {
        case .boolean: return tag == 1
        case .smallint: return tag == 3
        case .integer: return tag == 4
        case .bigint: return tag == 5
        case .real: return tag == 10
        case .doublePrecision: return tag == 11
        case .decimal: return tag == 12
        case .char, .varchar, .text: return tag == 13
        case .date: return tag == 15
        case .time(false, _): return tag == 16
        case .timestamp(false, _): return tag == 17
        case .timestamp(true, _): return tag == 18
        case .binary, .varbinary, .blob: return tag == 14
        case .uuid: return tag == 24
        default: return false
        }
    }
}
