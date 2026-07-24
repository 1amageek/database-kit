import DatabaseTypes
public struct ExecutionBudget: DatabaseWireValue, Hashable {
    public let maximumRows: UInt32
    public let maximumWorkUnits: UInt64
    public let maximumIntermediateRows: UInt32
    public let maximumIntermediateBytes: UInt64
    public let timeoutMilliseconds: UInt32

    public init(
        maximumRows: UInt32 = 10_000,
        maximumWorkUnits: UInt64 = 1_000_000,
        maximumIntermediateRows: UInt32 = 10_000,
        maximumIntermediateBytes: UInt64 = 16 * 1_024 * 1_024,
        timeoutMilliseconds: UInt32 = 30_000
    ) {
        self.maximumRows = maximumRows
        self.maximumWorkUnits = maximumWorkUnits
        self.maximumIntermediateRows = maximumIntermediateRows
        self.maximumIntermediateBytes = maximumIntermediateBytes
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    public func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        writer.writeUInt32(maximumRows)
        writer.writeUInt64(maximumWorkUnits)
        writer.writeUInt32(maximumIntermediateRows)
        writer.writeUInt64(maximumIntermediateBytes)
        writer.writeUInt32(timeoutMilliseconds)
    }

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        self.init(
            maximumRows: try reader.readUInt32(),
            maximumWorkUnits: try reader.readUInt64(),
            maximumIntermediateRows: try reader.readUInt32(),
            maximumIntermediateBytes: try reader.readUInt64(),
            timeoutMilliseconds: try reader.readUInt32()
        )
    }
}
