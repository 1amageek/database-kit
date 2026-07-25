import DatabaseKit
import DatabaseTypes

extension SchemaVersion: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt32(major)
        writer.writeUInt32(minor)
        writer.writeUInt32(patch)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            try reader.readUInt32(),
            try reader.readUInt32(),
            try reader.readUInt32()
        )
    }
}
