import DatabaseTypes
import DatabaseKit

/// Encodes and decodes recursive array data types without process-stack recursion.
enum QueryIRDataTypeWireCodec {
    static func encode(
        _ type: DataType,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        var encodingSteps: [EncodingStep] = [.dataType(type)]
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while let encodingStep = encodingSteps.popLast() {
            switch consume encodingStep {
            case .dataType(let value):
                try writer.beginNestedValue()
                openNestedValueCount += 1
                encodingSteps.append(.endNestedValue)
                try encodeContents(value, into: &writer, encodingSteps: &encodingSteps)

            case .endNestedValue:
                guard openNestedValueCount > 0 else {
                    throw .invalidQueryIRWireState
                }
                writer.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        guard openNestedValueCount == 0 else {
            throw .invalidQueryIRWireState
        }
    }

    static func decode(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DataType {
        var frames: [AssemblyFrame] = []
        var openNestedValueCount = 0
        defer {
            while openNestedValueCount > 0 {
                reader.endNestedValue()
                openNestedValueCount -= 1
            }
        }

        while true {
            try reader.beginNestedValue()
            openNestedValueCount += 1
            let tag = try reader.readUInt8()
            if tag == 20 {
                frames.append(.array)
                continue
            }

            var completed = try decodeScalar(tag: tag, from: &reader)
            reader.endNestedValue()
            openNestedValueCount -= 1

            while let frame = frames.popLast() {
                switch frame {
                case .array:
                    completed = .array(completed)
                }
                reader.endNestedValue()
                openNestedValueCount -= 1
            }
            return completed
        }
    }
}

private extension QueryIRDataTypeWireCodec {
    enum EncodingStep {
        case dataType(DataType)
        case endNestedValue
    }

    enum AssemblyFrame {
        case array
    }

    static func encodeContents(
        _ type: consuming DataType,
        into writer: inout DatabaseWireWriter,
        encodingSteps: inout [EncodingStep]
    ) throws(DatabaseWireError) {
        switch consume type {
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
            try QueryIRWireCodec.writeOptionalInt(precision, into: &writer)
            try QueryIRWireCodec.writeOptionalInt(scale, into: &writer)
        case .char(let length):
            writer.writeUInt8(7)
            try QueryIRWireCodec.writeOptionalInt(length, into: &writer)
        case .varchar(let length):
            writer.writeUInt8(8)
            try QueryIRWireCodec.writeOptionalInt(length, into: &writer)
        case .text:
            writer.writeUInt8(9)
        case .date:
            writer.writeUInt8(10)
        case .time(let withTimeZone):
            writer.writeUInt8(11)
            writer.writeBool(withTimeZone)
        case .timestamp(let withTimeZone):
            writer.writeUInt8(12)
            writer.writeBool(withTimeZone)
        case .interval:
            writer.writeUInt8(13)
        case .binary(let length):
            writer.writeUInt8(14)
            try QueryIRWireCodec.writeOptionalInt(length, into: &writer)
        case .varbinary(let length):
            writer.writeUInt8(15)
            try QueryIRWireCodec.writeOptionalInt(length, into: &writer)
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
        case .custom(let name):
            writer.writeUInt8(21)
            try writer.writeString(name)
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
                precision: try QueryIRWireCodec.readOptionalInt(from: &reader),
                scale: try QueryIRWireCodec.readOptionalInt(from: &reader)
            )
        case 7:
            return .char(
                length: try QueryIRWireCodec.readOptionalInt(from: &reader)
            )
        case 8:
            return .varchar(
                length: try QueryIRWireCodec.readOptionalInt(from: &reader)
            )
        case 9:
            return .text
        case 10:
            return .date
        case 11:
            return .time(withTimeZone: try reader.readBool())
        case 12:
            return .timestamp(withTimeZone: try reader.readBool())
        case 13:
            return .interval
        case 14:
            return .binary(
                length: try QueryIRWireCodec.readOptionalInt(from: &reader)
            )
        case 15:
            return .varbinary(
                length: try QueryIRWireCodec.readOptionalInt(from: &reader)
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
        default:
            throw .invalidValueTag(tag)
        }
    }
}
