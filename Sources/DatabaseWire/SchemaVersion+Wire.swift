import DatabaseTypes
import DatabaseValue

extension SchemaVersion: DatabaseWireValue {
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt32(major)
        writer.writeUInt32(minor)
        writer.writeUInt32(patch)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            try reader.readUInt32(),
            try reader.readUInt32(),
            try reader.readUInt32()
        )
    }
}
