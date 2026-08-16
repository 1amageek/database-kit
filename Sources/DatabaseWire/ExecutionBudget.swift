import DatabaseKit

extension ExecutionBudget: WireValue {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        writer.writeUInt32(maximumRows)
        writer.writeUInt64(maximumWorkUnits)
        writer.writeUInt32(maximumIntermediateRows)
        writer.writeUInt64(maximumIntermediateBytes)
        writer.writeUInt32(timeoutMilliseconds)
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init(
            maximumRows: try reader.readUInt32(),
            maximumWorkUnits: try reader.readUInt64(),
            maximumIntermediateRows: try reader.readUInt32(),
            maximumIntermediateBytes: try reader.readUInt64(),
            timeoutMilliseconds: try reader.readUInt32()
        )
    }
}
