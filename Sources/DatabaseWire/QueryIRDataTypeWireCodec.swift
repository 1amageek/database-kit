import DatabaseTypes
import DatabaseKit

/// Traverses arrays and composite descriptors with one cursor per open type.
enum QueryIRDataTypeWireCodec {
    static func encode(
        _ type: DataType,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.dataType(type)]
        var openNestedValueCount = 0
        defer { writer.abandonNestedValues(openNestedValueCount) }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .dataType(let value):
                if case .composite(let descriptor) = value {
                    let footprint: QueryValueFootprint
                    do throws(QueryValueError) { footprint = try descriptor.measure() }
                    catch let error { throw .invalidQueryValue(error) }
                    let actual = UInt64(writer.currentNestingDepth).addingReportingOverflow(footprint.maximumNestingDepth)
                    guard !actual.overflow else { throw .byteCountOverflow }
                    guard actual.partialValue <= UInt64(writer.limits.maximumNestingDepth) else {
                        throw .invalidQueryValue(.resourceLimit(resource: "depth", actual: actual.partialValue,
                            maximum: UInt64(writer.limits.maximumNestingDepth)))
                    }
                }
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .endNestedValue:
                guard openNestedValueCount > 0 else {
                    throw .invalidQueryIRWireState
                }
                try writer.endNestedValue()
                openNestedValueCount -= 1

            case .columns(let columns, let index):
                guard index < columns.count else { continue }
                let column = columns[index]
                encodingSteps.append(.columns(columns, index + 1))
                writer.writeUInt32(column.number)
                try writer.writeString(column.name)
                switch column.type {
                case .primitive(let kind, let isArray):
                    writer.writeUInt8(0)
                    try writer.writeString(kind.rawValue)
                    writer.writeBool(isArray)
                    writer.writeBool(column.isNullable)
                case .sql(let type):
                    writer.writeUInt8(1)
                    encodingSteps.append(.nullability(column.isNullable))
                    encodingSteps.append(.dataType(type))
                }

            case .nullability(let value):
                writer.writeBool(value)
            }
        }

        guard openNestedValueCount == 0 else {
            throw .invalidQueryIRWireState
        }
    }

    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataType {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        var frames: [AssemblyFrame] = []
        var openNestedValueCount = 0
        defer { reader.abandonNestedValues(openNestedValueCount) }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1
            let tag = try reader.readUInt8()
            if tag == 20 {
                frames.append(.array)
                continue
            }

            var completed: DataType
            if tag == 26 {
                completed = try decodeComposite(from: &reader)
            } else {
                completed = try decodeScalar(tag: tag, from: &reader)
            }
            try reader.endNestedValue()
            openNestedValueCount -= 1

            while let frame = frames.popLast() {
                switch frame {
                case .array:
                    completed = .array(completed)
                }
                try reader.endNestedValue()
                openNestedValueCount -= 1
            }
            return completed
        }
    }
}

extension QueryIRDataTypeWireCodec {
    enum EncodingStep {
        case dataType(DataType)
        case endNestedValue
        case columns(QueryCompositeColumns, Int)
        case nullability(Bool)
    }

    enum AssemblyFrame {
        case array
    }

    static func encodeContents(
        _ type: consuming DataType,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch type {
        case .boolean:
            writer.writeUInt8(0)
        case .smallint:
            writer.writeUInt8(1)
        case .integer:
            writer.writeUInt8(2)
        case .bigint:
            writer.writeUInt8(3)
        case .real:
            writer.writeUInt8(4)
        case .doublePrecision:
            writer.writeUInt8(5)
        case .decimal(let precision, let scale):
            writer.writeUInt8(6)
            try QueryIRWireFormat.writeOptionalInt(precision, into: &writer)
            try QueryIRWireFormat.writeOptionalInt(scale, into: &writer)
        case .char(let length):
            writer.writeUInt8(7)
            try QueryIRWireFormat.writeOptionalInt(length, into: &writer)
        case .varchar(let length):
            writer.writeUInt8(8)
            try QueryIRWireFormat.writeOptionalInt(length, into: &writer)
        case .text:
            writer.writeUInt8(9)
        case .date:
            writer.writeUInt8(10)
        case .time(let withTimeZone, let precision), .timestamp(let withTimeZone, let precision):
            let isTime: Bool
            if case .time = type { isTime = true } else { isTime = false }
            if let precision {
                guard (0...6).contains(precision) else { throw .invalidQueryValue(.incompatibleType) }
                writer.writeUInt8(isTime ? 22 : 23)
                writer.writeBool(withTimeZone)
                writer.writeUInt8(UInt8(precision))
            } else {
                writer.writeUInt8(isTime ? 11 : 12)
                writer.writeBool(withTimeZone)
            }
        case .interval(let fields, let precision):
            guard QueryValueValidator.accepts(.primitive(.null), type: .sql(type)) else {
                throw .invalidQueryValue(.incompatibleType)
            }
            if fields == nil && precision == nil { writer.writeUInt8(13) }
            else {
                writer.writeUInt8(25)
                writer.writeBool(fields != nil)
                if let fields { writer.writeUInt8(SQLTemporalWireCodec.encode(fields)) }
                writer.writeBool(precision != nil)
                if let precision { writer.writeUInt8(UInt8(precision)) }
            }
        case .binary(let length):
            writer.writeUInt8(14)
            try QueryIRWireFormat.writeOptionalInt(length, into: &writer)
        case .varbinary(let length):
            writer.writeUInt8(15)
            try QueryIRWireFormat.writeOptionalInt(length, into: &writer)
        case .blob:
            writer.writeUInt8(16)
        case .json:
            writer.writeUInt8(17)
        case .jsonb:
            writer.writeUInt8(18)
        case .uuid:
            writer.writeUInt8(19)
        case .array(let element):
            writer.writeUInt8(20)
            encodingSteps.append(.dataType(element))
        case .custom(let name, let schema):
            writer.writeUInt8(schema == nil ? 21 : 24)
            if let schema { try writer.writeString(schema) }
            try writer.writeString(name)
        case .composite(let descriptor):
            writer.writeUInt8(26)
            try writer.writeCount(descriptor.columns.count)
            encodingSteps.append(.columns(descriptor.columns, 0))
        }
    }

    struct CompositeFrame {
        let count: Int
        var columns: [QueryTypeColumn] = []
        var number: UInt32?
        var name: String?
    }

    enum TypeFrame {
        case array
        case composite(CompositeFrame)
    }

    /// The caller has opened the root tag26 scope. All child descriptors are
    /// appended to the same flat builder, never rebuilt as intermediate owners.
    static func decodeComposite(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> DataType {
        var builder = QueryTypeBuilder(limits: reader.queryTypeConstructionLimits)
        var frames: [TypeFrame] = [.composite(CompositeFrame(count: try reader.readCount()))]
        var open = 0
        defer { reader.abandonNestedValues(open) }
        var completed: Int?

        while true {
            if let child = completed {
                completed = nil
                guard let frame = frames.popLast() else {
                    let type: DataType
                    do throws(QueryValueError) { type = try builder.finish(root: child) }
                    catch let error { throw .invalidQueryValue(error) }
                    if case .composite(let descriptor) = type {
                        try reader.registerQueryTypeStorage(descriptor.storageFootprint)
                    }
                    return type
                }
                switch frame {
                case .array:
                    do throws(QueryValueError) { completed = try builder.appendArray(element: child) }
                    catch let error { throw .invalidQueryValue(error) }
                    try reader.endNestedValue()
                    open -= 1
                case .composite(var state):
                    guard let number = state.number, let name = state.name else {
                        throw .invalidQueryIRWireState
                    }
                    let nullable = try reader.readBool()
                    state.columns.append(QueryTypeColumn(number: number, name: name, type: child, isNullable: nullable))
                    state.number = nil
                    state.name = nil
                    frames.append(.composite(state))
                }
                continue
            }

            guard let frame = frames.popLast() else { throw .invalidQueryIRWireState }
            switch frame {
            case .array:
                throw .invalidQueryIRWireState
            case .composite(var state):
                if state.columns.count == state.count {
                    do throws(QueryValueError) { completed = try builder.appendComposite(columns: state.columns) }
                    catch let error { throw .invalidQueryValue(error) }
                    if !frames.isEmpty {
                        try reader.endNestedValue()
                        open -= 1
                    }
                    continue
                }
                let number = try reader.readUInt32()
                guard UInt64(number) == UInt64(state.columns.count) + 1 else {
                    throw .invalidQueryValue(.invalidColumnNumber(number))
                }
                state.number = number
                state.name = try reader.readString()
                let columnTag = try reader.readUInt8()
                if columnTag == 0 {
                    let raw = try reader.readString()
                    guard let kind = FieldSchemaType(rawValue: raw) else { throw .invalidQueryValue(.incompatibleType) }
                    let isArray = try reader.readBool()
                    do throws(QueryValueError) { completed = try builder.append(.primitive(kind, isArray: isArray)) }
                    catch let error { throw .invalidQueryValue(error) }
                    frames.append(.composite(state))
                    continue
                }
                guard columnTag == 1 else { throw .invalidValueTag(columnTag) }
                frames.append(.composite(state))
            }

            // Follow the selected SQL field type without another decoder call.
            while true {
                try reader.beginNestedValue()
                open += 1
                let tag = try reader.readUInt8()
                if tag == 20 {
                    frames.append(.array)
                    continue
                }
                if tag == 26 {
                    frames.append(.composite(CompositeFrame(count: try reader.readCount())))
                    break
                }
                let scalar = try decodeScalar(tag: tag, from: &reader)
                do throws(QueryValueError) { completed = try builder.append(.sql(scalar)) }
                catch let error { throw .invalidQueryValue(error) }
                try reader.endNestedValue()
                open -= 1
                break
            }
        }
    }

    static func decodeScalar(
        tag: UInt8,
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataType {
        switch tag {
        case 0:
            return .boolean
        case 1:
            return .smallint
        case 2:
            return .integer
        case 3:
            return .bigint
        case 4:
            return .real
        case 5:
            return .doublePrecision
        case 6:
            return .decimal(
                precision: try QueryIRWireFormat.readOptionalInt(from: &reader),
                scale: try QueryIRWireFormat.readOptionalInt(from: &reader)
            )
        case 7:
            return .char(
                length: try QueryIRWireFormat.readOptionalInt(from: &reader)
            )
        case 8:
            return .varchar(
                length: try QueryIRWireFormat.readOptionalInt(from: &reader)
            )
        case 9:
            return .text
        case 10:
            return .date
        case 11:
            return .time(withTimeZone: try reader.readBool())
        case 12:
            return .timestamp(withTimeZone: try reader.readBool())
        case 22, 23:
            let withTimeZone = try reader.readBool()
            let precision = try reader.readUInt8()
            guard precision <= 6 else { throw .invalidQueryValue(.incompatibleType) }
            return tag == 22 ? .time(withTimeZone: withTimeZone, precision: Int(precision))
                : .timestamp(withTimeZone: withTimeZone, precision: Int(precision))
        case 13:
            return .interval()
        case 25:
            let fields: SQLIntervalFields?
            if try reader.readBool() { fields = try SQLTemporalWireCodec.intervalFields(reader.readUInt8()) }
            else { fields = nil }
            let precision: Int?
            if try reader.readBool() { precision = Int(try reader.readUInt8()) }
            else { precision = nil }
            let type = DataType.interval(fields: fields, precision: precision)
            guard fields != nil || precision != nil,
                  QueryValueValidator.accepts(.primitive(.null), type: .sql(type)) else {
                throw .invalidQueryValue(.incompatibleType)
            }
            return type
        case 14:
            return .binary(
                length: try QueryIRWireFormat.readOptionalInt(from: &reader)
            )
        case 15:
            return .varbinary(
                length: try QueryIRWireFormat.readOptionalInt(from: &reader)
            )
        case 16:
            return .blob
        case 17:
            return .json
        case 18:
            return .jsonb
        case 19:
            return .uuid
        case 21:
            return .custom(try reader.readString())
        case 24:
            let schema = try reader.readString()
            return .custom(try reader.readString(), schema: schema)
        default:
            throw .invalidValueTag(tag)
        }
    }
}
