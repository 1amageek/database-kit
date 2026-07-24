import DatabaseTypes
import DatabaseValue

public struct DatabaseTypedWriteCommandResponse<Output: DatabaseWireValue>:
    DatabaseWireValue {
    public let output: Output
    public let commitVersion: UInt64
    public let continuation: ByteString?

    public init(
        output: Output,
        commitVersion: UInt64,
        continuation: ByteString? = nil
    ) {
        self.output = output
        self.commitVersion = commitVersion
        self.continuation = continuation
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try output.encode(into: &payloadWriter)
        }
        writer.writeUInt64(commitVersion)
        try writer.writeOptionalBytes(continuation)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let output = try reader.readLengthPrefixed {
            (payloadReader: inout DatabaseWireReader) throws(DatabaseWireError) in
            try Output(from: &payloadReader)
        }
        self.init(
            output: output,
            commitVersion: try reader.readUInt64(),
            continuation: try reader.readOptionalBytes()
        )
    }
}
