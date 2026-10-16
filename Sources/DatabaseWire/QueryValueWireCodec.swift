import DatabaseKit
import DatabaseTypes

enum QueryValueWireCodec {
    private enum EncodingStep {
        case value(QueryValue)
        case children(QueryValueElements, Int)
        case end
    }

    static func encode(_ value: QueryValue, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        if case .array = value { try admitCollectionDepth(value, writer: &writer) }
        else if case .composite = value { try admitCollectionDepth(value, writer: &writer) }
        var steps: [EncodingStep] = [.value(value)]
        var open = 0
        defer { writer.abandonNestedValues(open) }
        while let step = steps.popLast() {
            switch step {
            case .value(.array(let array)):
                try writer.beginNestedValue()
                open += 1
                writer.writeUInt8(4)
                try QueryIRDataTypeWireCodec.encode(array.elementType, into: &writer)
                try writer.writeCount(array.dimensions.count)
                for dimension in array.dimensions {
                    writer.writeInt32(dimension.lowerBound)
                    writer.writeInt32(dimension.length)
                }
                try writer.writeCount(array.elements.count)
                steps.append(.end)
                steps.append(.children(array.elements, 0))
            case .value(.composite(let composite)):
                try writer.beginNestedValue()
                open += 1
                writer.writeUInt8(11)
                try QueryIRDataTypeWireCodec.encode(.composite(composite.type), into: &writer)
                try writer.writeCount(composite.fields.count)
                steps.append(.end)
                steps.append(.children(composite.fields, 0))
            case .value(let scalar):
                try encodeScalar(scalar, into: &writer)
            case .children(let values, let index):
                guard index < values.count else { continue }
                steps.append(.children(values, index + 1))
                steps.append(.value(values[index]))
            case .end:
                try writer.endNestedValue()
                open -= 1
            }
        }
    }

    private static func admitCollectionDepth(_ value: QueryValue, writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        let footprint: QueryValueFootprint
        do throws(QueryValueError) { footprint = try QueryValueValidator.measure(value) }
        catch let error { throw .invalidQueryValue(error) }
        let actual = UInt64(writer.currentNestingDepth).addingReportingOverflow(footprint.maximumNestingDepth)
        guard !actual.overflow else { throw .byteCountOverflow }
        guard actual.partialValue <= UInt64(writer.limits.maximumNestingDepth) else {
            throw .invalidQueryValue(.resourceLimit(resource: "depth", actual: actual.partialValue,
                maximum: UInt64(writer.limits.maximumNestingDepth)))
        }
    }

    private static func encodeScalar(_ value: QueryValue, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch value {
        case .primitive(let primitive):
            writer.writeUInt8(0)
            try FieldValueWireCodec.encode(primitive, into: &writer)
        case .jsonb(let jsonb):
            writer.writeUInt8(3)
            try QueryJSONBWireCodec.encode(jsonb.root, into: &writer)
        case .numeric, .json, .interval, .time, .timeWithTimeZone, .dateInfinity, .timestampInfinity, .intervalInfinity:
            try writer.withNestedValue { writer throws(DatabaseWireError) in
                switch value {
                case .numeric(let numeric): writer.writeUInt8(1); encodeNumeric(numeric, into: &writer)
                case .json(let json):
                    writer.writeUInt8(2)
                    try chargeJSON(try jsonFootprint(json), writer: &writer)
                    try writer.writeBytes(json.bytes)
                case .time(let value):
                    writer.writeUInt8(6)
                    writer.writeInt64(value.microsecondsSinceMidnight)
                case .timeWithTimeZone(let value):
                    writer.writeUInt8(7)
                    writer.writeInt64(value.time.microsecondsSinceMidnight)
                    writer.writeInt32(value.utcOffsetSeconds)
                case .dateInfinity(let direction):
                    writer.writeUInt8(8)
                    writer.writeUInt8(SQLTemporalWireCodec.encode(direction))
                case .timestampInfinity(let direction, let withTimeZone):
                    writer.writeUInt8(9)
                    writer.writeUInt8(SQLTemporalWireCodec.encode(direction))
                    writer.writeBool(withTimeZone)
                case .intervalInfinity(let direction):
                    writer.writeUInt8(10)
                    writer.writeUInt8(SQLTemporalWireCodec.encode(direction))
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
        case .array, .composite: throw .invalidQueryValue(.incompatibleType)
        }
    }

    private enum CollectionDescriptor {
        case array(DataType, [QueryArrayDimension])
        case composite(QueryCompositeType)
    }

    private struct CollectionFrame {
        let descriptor: CollectionDescriptor
        let count: Int
        var children: [Int] = []
    }

    static func decode(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryValue {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        var builder = QueryValueBuilder(admittedLimits: reader.queryValueConstructionLimits)
        var frames: [CollectionFrame] = []
        var completed: Int?
        var open = 0
        defer { reader.abandonNestedValues(open) }
        while true {
            if let child = completed {
                completed = nil
                guard var frame = frames.popLast() else {
                    let value: QueryValue
                    do throws(QueryValueError) { value = try builder.finish(root: child) }
                    catch let error { throw .invalidQueryValue(error) }
                    switch value {
                    case .array(let array): try reader.registerQueryValueStorage(array.storageFootprint)
                    case .composite(let composite): try reader.registerQueryValueStorage(composite.storageFootprint)
                    default: break
                    }
                    return value
                }
                frame.children.append(child)
                frames.append(frame)
            }
            if let frame = frames.last, frame.children.count == frame.count {
                _ = frames.popLast()
                do throws(QueryValueError) {
                    switch frame.descriptor {
                    case .array(let type, let dimensions):
                        completed = try builder.appendArray(elementType: type, dimensions: dimensions, elements: frame.children)
                    case .composite(let type):
                        completed = try builder.appendComposite(type: type, fields: frame.children)
                    }
                } catch let error { throw .invalidQueryValue(error) }
                try reader.endNestedValue()
                open -= 1
                continue
            }
            let tag = try reader.readUInt8()
            if tag == 4 || tag == 11 {
                try reader.beginNestedValue()
                open += 1
                let descriptor: CollectionDescriptor
                let count: Int
                if tag == 4 {
                    let shape = try decodeArrayShape(from: &reader)
                    descriptor = .array(shape.type, shape.dimensions)
                    count = shape.count
                } else {
                    guard case .composite(let type) = try QueryIRDataTypeWireCodec.decode(from: &reader) else {
                        throw .invalidQueryValue(.incompatibleType)
                    }
                    count = try reader.readCount()
                    guard count == type.columns.count else {
                        throw .invalidQueryValue(.compositeFieldCountMismatch(expected: UInt64(type.columns.count), actual: UInt64(count)))
                    }
                    descriptor = .composite(type)
                }
                var frame = CollectionFrame(descriptor: descriptor, count: count)
                frame.children.reserveCapacity(count)
                frames.append(frame)
            } else {
                let scalar = try decodeScalar(tag: tag, from: &reader)
                do throws(QueryValueError) { completed = try builder.append(scalar) }
                catch let error { throw .invalidQueryValue(error) }
            }
        }
    }

    static func validate(from reader: inout DatabaseWireReader, type: QueryColumnType? = nil,
                         isNullable: Bool = true) throws(DatabaseWireError) {
        try QueryValueWireValidator.validate(from: &reader, type: type, isNullable: isNullable)
    }

    static func decodeScalar(tag: UInt8, from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryValue {
        switch tag {
        case 0: return .primitive(try FieldValueWireCodec.decodeValue(from: &reader))
        case 3: return .jsonb(try QueryJSONBWireCodec.decode(from: &reader))
        case 6...10:
            return try reader.withNestedValue { reader throws(DatabaseWireError) in
                try decodeTemporalPayload(tag: tag, from: &reader)
            }
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

    static func decodeTemporalPayload(tag: UInt8, from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryValue {
        switch tag {
        case 6, 7:
            let micros = try reader.readInt64()
            let time: QueryTimeValue
            do throws(QueryValueError) { time = try QueryTimeValue(microsecondsSinceMidnight: micros) }
            catch let error { throw .invalidQueryValue(error) }
            if tag == 6 { return .time(time) }
            return .timeWithTimeZone(QueryTimeWithTimeZoneValue(time: time, utcOffsetSeconds: try reader.readInt32()))
        case 8: return .dateInfinity(try SQLTemporalWireCodec.infinity(reader.readUInt8()))
        case 9:
            let direction = try SQLTemporalWireCodec.infinity(reader.readUInt8())
            return .timestampInfinity(direction, withTimeZone: try reader.readBool())
        case 10: return .intervalInfinity(try SQLTemporalWireCodec.infinity(reader.readUInt8()))
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
