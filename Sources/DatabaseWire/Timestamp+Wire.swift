import DatabaseTypes

extension Timestamp: WireValue {}

@_spi(DatabaseExecution)
public extension Timestamp {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeInt64(secondsSinceUnixEpoch)
        writer.writeUInt32(nanoseconds)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        do {
            try self.init(
                secondsSinceUnixEpoch: reader.readInt64(),
                nanoseconds: reader.readUInt32()
            )
        } catch {
            throw .invalidTimestamp
        }
    }
}
