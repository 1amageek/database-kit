import DatabaseKit
import DatabaseTypes

/// Validates lazy cells in place without building primitive or JSONB trees.
enum QueryValueWireValidator {
    private enum Mismatch {
        case array(Int)
        case composite(Int)
    }
    private enum Step {
        case value(QueryWireExpectedType?, Bool, Mismatch?, depth: Int)
        case array(remaining: Int, index: Int, type: QueryWireTypeView, depth: Int)
        case composite(QueryWireColumnCursor, depth: Int)
        case end
    }

    static func validate(from reader: inout DatabaseWireReader, type: QueryColumnType? = nil,
                         isNullable: Bool = true) throws(DatabaseWireError) {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        var steps: [Step] = [.value(type.map { .declared($0) }, isNullable, nil, depth: reader.currentNestingDepth + 1)]
        var open = 0
        defer { reader.abandonNestedValues(open) }
        while let step = steps.popLast() {
            switch step {
            case .end:
                try reader.endNestedValue()
                open -= 1
            case .array(let remaining, let index, let type, let depth):
                guard remaining > 0 else { continue }
                steps.append(.array(remaining: remaining - 1, index: index + 1, type: type, depth: depth))
                steps.append(.value(.encoded(type), true, .array(index), depth: depth + 1))
            case .composite(var cursor, let depth):
                guard cursor.index < cursor.count else { continue }
                let index = cursor.index
                let column = try cursor.next()
                steps.append(.composite(cursor, depth: depth))
                steps.append(.value(.encoded(column.type), column.isNullable, .composite(index), depth: depth + 1))
            case .value(let type, let nullable, let mismatch, let depth):
                do throws(DatabaseWireError) {
                    let tag = try reader.readUInt8()
                    if tag == 4 || tag == 11 {
                        try reader.beginNestedValue()
                        open += 1
                        steps.append(.end)
                        let descriptor = try QueryTypeWireValidator.validate(from: &reader)
                        let actualDepth = UInt64(depth).addingReportingOverflow(descriptor.maximumNestingDepth)
                        guard !actualDepth.overflow else { throw .byteCountOverflow }
                        guard actualDepth.partialValue <= UInt64(reader.limits.maximumNestingDepth) else {
                            throw .invalidQueryValue(.resourceLimit(resource: "depth", actual: actualDepth.partialValue,
                                maximum: UInt64(reader.limits.maximumNestingDepth)))
                        }
                        if tag == 4 {
                            if case .array = descriptor.shape { throw .invalidQueryValue(.incompatibleType) }
                            if let type {
                                guard try QueryTypeWireValidator.matches(descriptor, expected: type.arrayElement()) else {
                                    throw .invalidQueryValue(.incompatibleType)
                                }
                            }
                            let dimensions = try reader.readCount()
                            guard dimensions <= 6 else { throw .invalidQueryValue(.invalidDimensionCount(dimensions)) }
                            var product: UInt64 = dimensions == 0 ? 0 : 1
                            for _ in 0..<dimensions {
                                let lower = try reader.readInt32()
                                let length = try reader.readInt32()
                                do throws(QueryValueError) { _ = try QueryArrayDimension(lowerBound: lower, length: length) }
                                catch let error { throw .invalidQueryValue(error) }
                                let next = product.multipliedReportingOverflow(by: UInt64(length))
                                guard !next.overflow else { throw .invalidQueryValue(.dimensionProductOverflow) }
                                product = next.partialValue
                            }
                            let count = try reader.readCount()
                            guard product == UInt64(count) else {
                                throw .invalidQueryValue(.elementCountMismatch(expected: product, actual: UInt64(count)))
                            }
                            steps.append(.array(remaining: count, index: 0, type: descriptor, depth: depth))
                        } else {
                            guard case .composite(let columns) = descriptor.shape else { throw .invalidQueryValue(.incompatibleType) }
                            if let type {
                                guard try QueryTypeWireValidator.matches(descriptor, expected: type) else {
                                    throw .invalidQueryValue(.incompatibleType)
                                }
                            }
                            let count = try reader.readCount()
                            guard count == columns else {
                                throw .invalidQueryValue(.compositeFieldCountMismatch(expected: UInt64(columns), actual: UInt64(count)))
                            }
                            steps.append(.composite(try descriptor.columns(), depth: depth))
                        }
                    } else {
                        if tag == 0 {
                            var probe = reader
                            let primitiveTag = try probe.readUInt8()
                            if primitiveTag == 0, !nullable, case .some(.composite(let index)) = mismatch {
                                throw .invalidQueryValue(.nullCompositeField(index: UInt64(index)))
                            }
                            if let type, type.scalar == nil, primitiveTag != 0 {
                                try rejectIncompatiblePrimitive(from: reader)
                            }
                        } else if let type, type.scalar == nil {
                            throw .invalidQueryValue(.incompatibleType)
                        }
                        try validateScalar(tag: tag, from: &reader, type: type?.scalar, isNullable: nullable)
                    }
                } catch .invalidQueryValue(.incompatibleType) {
                    switch mismatch {
                    case .some(.array(let index)), .some(.composite(let index)):
                        throw .invalidQueryValue(.elementTypeMismatch(index: UInt64(index)))
                    case nil: throw .invalidQueryValue(.incompatibleType)
                    }
                } catch let error { throw error }
            }
        }
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
        case 6...10:
            try reader.withNestedValue { reader throws(DatabaseWireError) in
                let value = try QueryValueWireCodec.decodeTemporalPayload(tag: tag, from: &reader)
                if let type, !QueryValueValidator.accepts(value, type: type) {
                    throw .invalidQueryValue(.incompatibleType)
                }
            }
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
                    let value = try QueryValueWireCodec.decodeInterval(from: &reader)
                    if let type, !QueryValueValidator.accepts(.interval(value), type: type) {
                        throw .invalidQueryValue(.incompatibleType)
                    }
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
