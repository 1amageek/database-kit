/// Runtime field value used by wire queries and records.
public enum DatabaseWireFieldValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int64(Int64)
    case double(Double)
    case string(String)
    case bytes([UInt8])
    case array([DatabaseWireFieldValue])
    case object([DatabaseWireNamedValue])
    case reference(String)

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        switch self {
        case .null:
            writer.writeUInt8(0)
        case .bool(let value):
            writer.writeUInt8(1)
            writer.writeBool(value)
        case .int64(let value):
            writer.writeUInt8(2)
            writer.writeInt64(value)
        case .double(let value):
            writer.writeUInt8(3)
            writer.writeDouble(value)
        case .string(let value):
            writer.writeUInt8(4)
            try writer.writeString(value)
        case .bytes(let value):
            writer.writeUInt8(5)
            try writer.writeBytes(value)
        case .array(let values):
            writer.writeUInt8(6)
            try writer.writeCount(values.count)
            for value in values {
                try value.encode(into: &writer)
            }
        case .object(let fields):
            writer.writeUInt8(7)
            try writer.writeCount(fields.count)
            for field in fields {
                try field.encode(into: &writer)
            }
        case .reference(let id):
            writer.writeUInt8(8)
            try writer.writeString(id)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        switch tag {
        case 0:
            self = .null
        case 1:
            self = .bool(try reader.readBool())
        case 2:
            self = .int64(try reader.readInt64())
        case 3:
            self = .double(try reader.readDouble())
        case 4:
            self = .string(try reader.readString())
        case 5:
            self = .bytes(try reader.readBytes())
        case 6:
            let count = try reader.readCount()
            var values: [DatabaseWireFieldValue] = []
            values.reserveCapacity(count)
            for _ in 0..<count {
                values.append(try DatabaseWireFieldValue(from: &reader))
            }
            self = .array(values)
        case 7:
            let count = try reader.readCount()
            var fields: [DatabaseWireNamedValue] = []
            fields.reserveCapacity(count)
            for _ in 0..<count {
                fields.append(try DatabaseWireNamedValue(from: &reader))
            }
            self = .object(fields)
        case 8:
            self = .reference(try reader.readString())
        default:
            throw DatabaseWireError.unknownFieldValue(tag)
        }
    }
}
