public import DatabaseValue

extension DatabaseUUID: DatabaseWireValue {
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt64(high)
        writer.writeUInt64(low)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            high: try reader.readUInt64(),
            low: try reader.readUInt64()
        )
    }
}
