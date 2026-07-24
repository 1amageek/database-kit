import DatabaseTypes
import DatabaseValue

public struct DatabaseTypedReadCommandResponse<Output: DatabaseWireValue>:
    DatabaseWireValue {
    public let output: Output
    public let continuation: ByteString?

    public init(
        output: Output,
        continuation: ByteString? = nil
    ) {
        self.output = output
        self.continuation = continuation
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try output.encode(into: &payloadWriter)
        }
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
            continuation: try reader.readOptionalBytes()
        )
    }
}
