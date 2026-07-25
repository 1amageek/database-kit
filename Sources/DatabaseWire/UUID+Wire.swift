import DatabaseTypes

extension DatabaseTypes.UUID: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt64(high)
        writer.writeUInt64(low)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            high: try reader.readUInt64(),
            low: try reader.readUInt64()
        )
    }
}
