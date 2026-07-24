import DatabaseTypes

public struct ReadCommandResult<Output: DatabaseWireValue>: CommandResult {
    public static var access: CommandAccess { .readOnly }

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
        try Self.access.encode(into: &writer)
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try output.encode(into: &payloadWriter)
        }
        try writer.writeOptionalBytes(continuation)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let actualAccess = try CommandAccess(from: &reader)
        guard actualAccess == Self.access else {
            throw .mismatchedCommandAccess(
                expected: Self.access.rawValue,
                actual: actualAccess.rawValue
            )
        }
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
