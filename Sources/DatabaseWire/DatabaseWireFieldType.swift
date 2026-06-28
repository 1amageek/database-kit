/// Field type metadata supported by DatabaseKit wire runtime.
public enum DatabaseWireFieldType: UInt8, Sendable, Hashable {
    case bool = 1
    case int64 = 2
    case double = 3
    case string = 4
    case bytes = 5
    case array = 6
    case object = 7
    case reference = 8

    public func encode(into writer: inout DatabaseWireBinaryWriter) {
        writer.writeUInt8(rawValue)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        guard let value = DatabaseWireFieldType(rawValue: tag) else {
            throw DatabaseWireError.unknownFieldType(tag)
        }
        self = value
    }
}
