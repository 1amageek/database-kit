public import DatabaseValue

extension DatabaseTimestamp: DatabaseWireValue {
    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeInt64(secondsSinceUnixEpoch)
        writer.writeUInt32(nanoseconds)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            secondsSinceUnixEpoch: try reader.readInt64(),
            nanoseconds: try reader.readUInt32()
        )
    }
}
