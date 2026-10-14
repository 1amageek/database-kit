import DatabaseKit
import DatabaseTypes

enum QueryValueWireCodec {
    static func encode(_ value: QueryValue, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        if case .array(let array) = value {
            try writer.beginNestedValue()
            var open = true
            defer { if open { writer.abandonNestedValues(1) } }
            writer.writeUInt8(4)
            try QueryIRDataTypeWireCodec.encode(array.elementType, into: &writer)
            try writer.writeCount(array.dimensions.count)
            for dimension in array.dimensions {
                writer.writeInt32(dimension.lowerBound)
                writer.writeInt32(dimension.length)
            }
            try writer.writeCount(array.elements.count)
            for element in array.elements { try encodeScalar(element, into: &writer) }
            try writer.endNestedValue()
            open = false
        } else { try encodeScalar(value, into: &writer) }
    }

    private static func encodeScalar(_ value: QueryValue, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch value {
        case .primitive(let primitive):
            writer.writeUInt8(0)
            try FieldValueWireCodec.encode(primitive, into: &writer)
        case .jsonb(let jsonb):
            writer.writeUInt8(3)
            try QueryJSONBWireCodec.encode(jsonb.root, into: &writer)
        case .numeric, .json, .interval:
            try writer.withNestedValue { writer throws(DatabaseWireError) in
                switch value {
                case .numeric(let numeric): writer.writeUInt8(1); encodeNumeric(numeric, into: &writer)
                case .json(let json):
                    writer.writeUInt8(2)
                    try chargeJSON(try jsonFootprint(json), writer: &writer)
                    try writer.writeBytes(json.bytes)
                case .interval(let interval):
                    writer.writeUInt8(5)
                    guard let months = Int32(exactly: interval.period.months),
                          let days = Int32(exactly: interval.period.days) else {
                        throw .invalidQueryValue(.intervalOutOfRange)
                    }
                    writer.writeInt32(months)
                    writer.writeInt32(days)
                    writer.writeInt64(interval.microseconds)
                default: throw .invalidQueryIRWireState
                }
            }
        case .array: throw .invalidQueryValue(.incompatibleType)
        }
    }

    static func decode(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryValue {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        let tag = try reader.readUInt8()
        guard tag == 4 else { return try decodeScalar(tag: tag, from: &reader) }
        try reader.beginNestedValue()
        var open = true
        defer { if open { reader.abandonNestedValues(1) } }
        let shape = try decodeArrayShape(from: &reader)
        var elements: [QueryValue] = []
        elements.reserveCapacity(shape.count)
        for index in 0..<shape.count {
            let value: QueryValue
            do throws(DatabaseWireError) {
                let elementTag = try reader.readUInt8()
                value = try decodeScalar(tag: elementTag, from: &reader)
            } catch .invalidQueryValue(.incompatibleType) {
                throw .invalidQueryValue(.elementTypeMismatch(index: UInt64(index)))
            } catch let error { throw error }
            guard QueryValueValidator.accepts(value, type: .sql(shape.type)) else {
                throw .invalidQueryValue(.elementTypeMismatch(index: UInt64(index)))
            }
            elements.append(value)
        }
        let array: QueryArrayValue
        do throws(QueryValueError) {
            array = try QueryArrayValue(admittedElementType: shape.type, dimensions: shape.dimensions, elements: elements)
        } catch let error { throw .invalidQueryValue(error) }
        try reader.endNestedValue()
        open = false
        return .array(array)
    }

    static func validate(from reader: inout DatabaseWireReader, type: QueryColumnType? = nil,
                         isNullable: Bool = true) throws(DatabaseWireError) {
        try QueryValueWireValidator.validate(from: &reader, type: type, isNullable: isNullable)
    }

    static func decodeScalar(tag: UInt8, from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryValue {
        switch tag {
        case 0: return .primitive(try FieldValueWireCodec.decodeValue(from: &reader))
        case 3: return .jsonb(try QueryJSONBWireCodec.decode(from: &reader))
        case 1, 2, 5:
            return try reader.withNestedValue { reader throws(DatabaseWireError) in
                switch tag {
                case 1: return .numeric(try decodeNumeric(from: &reader))
                case 2:
                    let json = try decodeJSON(from: &reader)
                    try reader.registerQueryJSONFootprint(try jsonFootprint(json))
                    return .json(json)
                case 5: return .interval(try decodeInterval(from: &reader))
                default: throw .invalidQueryIRWireState
                }
            }
        case 4: throw .invalidQueryValue(.incompatibleType)
        default: throw .invalidValueTag(tag)
        }
    }

    static func encodeNumeric(_ value: QueryNumericValue, into writer: inout DatabaseWireWriter) {
        writer.writeInt128(value.value.coefficient)
        writer.writeInt32(value.value.scale)
        writer.writeInt32(value.displayScale)
    }

    static func decodeNumeric(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryNumericValue {
        let coefficient = try reader.readInt128()
        let scale = try reader.readInt32()
        let displayScale = try reader.readInt32()
        let value = ExactDecimal(coefficient: coefficient, scale: scale)
        guard coefficient == value.coefficient, scale == value.scale else {
            throw .invalidQueryValue(.numericOutOfRange)
        }
        do throws(QueryValueError) { return try QueryNumericValue(value: value, displayScale: displayScale) }
        catch let error { throw .invalidQueryValue(error) }
    }

    static func decodeJSON(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryJSONValue {
        let bytes = try reader.readBytes()
        do throws(QueryValueError) { return try QueryJSONValue(bytes: bytes, limits: reader.queryValueLimits) }
        catch let error { throw .invalidQueryValue(error) }
    }

    static func jsonFootprint(_ json: QueryJSONValue) throws(DatabaseWireError) -> QueryValueFootprint {
        do throws(QueryValueError) { return try json.measure() }
        catch let error { throw .invalidQueryValue(error) }
    }

    static func decodeInterval(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryIntervalValue {
        let months = try reader.readInt32()
        let days = try reader.readInt32()
        let micros = try reader.readInt64()
        var seconds = micros / 1_000_000
        var remainder = micros % 1_000_000
        if remainder < 0 { seconds -= 1; remainder += 1_000_000 }
        let time: TimeSpan
        do { time = try TimeSpan(seconds: seconds, nanoseconds: UInt32(remainder) * 1000) }
        catch let error { throw .invalidTimeSpan(error) }
        do throws(QueryValueError) {
            return try QueryIntervalValue(period: CalendarPeriod(months: Int64(months), days: Int64(days)), time: time)
        } catch let error { throw .invalidQueryValue(error) }
    }

    static func decodeArrayShape(from reader: inout DatabaseWireReader) throws(DatabaseWireError)
        -> (type: DataType, dimensions: [QueryArrayDimension], count: Int) {
        let type = try QueryIRDataTypeWireCodec.decode(from: &reader)
        if case .array = type { throw .invalidQueryValue(.incompatibleType) }
        guard QueryValueValidator.accepts(.primitive(.null), type: .sql(type)) else {
            throw .invalidQueryValue(.incompatibleType)
        }
        let dimensionCount = try reader.readCount()
        guard dimensionCount <= 6 else { throw .invalidQueryValue(.invalidDimensionCount(dimensionCount)) }
        var dimensions: [QueryArrayDimension] = []
        var product: UInt64 = dimensionCount == 0 ? 0 : 1
        for _ in 0..<dimensionCount {
            let lower = try reader.readInt32()
            let length = try reader.readInt32()
            let dimension: QueryArrayDimension
            do throws(QueryValueError) { dimension = try QueryArrayDimension(lowerBound: lower, length: length) }
            catch let error { throw .invalidQueryValue(error) }
            let next = product.multipliedReportingOverflow(by: UInt64(length))
            guard !next.overflow else { throw .invalidQueryValue(.dimensionProductOverflow) }
            product = next.partialValue
            dimensions.append(dimension)
        }
        let count = try reader.readCount()
        guard product == UInt64(count) else {
            throw .invalidQueryValue(.elementCountMismatch(expected: product, actual: UInt64(count)))
        }
        return (type, dimensions, count)
    }

    private static func chargeJSON(_ footprint: QueryValueFootprint, writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        let depth = UInt64(writer.currentNestingDepth).addingReportingOverflow(footprint.maximumNestingDepth - 1)
        guard !depth.overflow, depth.partialValue <= UInt64(writer.limits.maximumNestingDepth) else {
            throw .invalidQueryValue(.resourceLimit(resource: "depth", actual: depth.partialValue,
                                                  maximum: UInt64(writer.limits.maximumNestingDepth)))
        }
        let count = (footprint.nodeCount - 1).addingReportingOverflow(footprint.collectionElementCount)
        guard !count.overflow, let objectCount = Int(exactly: count.partialValue) else { throw .byteCountOverflow }
        try writer.registerObjects(objectCount)
    }
}
