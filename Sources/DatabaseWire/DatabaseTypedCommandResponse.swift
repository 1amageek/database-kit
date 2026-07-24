import DatabaseTypes
import DatabaseValue

public struct DatabaseTypedCommandResponse<
    Command: DatabaseCommandDescriptor
>: DatabaseWireValue {
    public let output: Command.Output
    public let commitVersion: UInt64?
    public let continuation: ByteString?

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try Command.access.encode(into: &writer)
        try writer.writeLengthPrefixed {
            (payloadWriter: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try output.encode(into: &payloadWriter)
        }
        if let commitVersion {
            writer.writeUInt64(commitVersion)
        }
        try writer.writeOptionalBytes(continuation)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let actualAccess = try DatabaseCommandAccess(from: &reader)
        guard actualAccess == Command.access else {
            throw .mismatchedCommandAccess(
                expected: Command.access.rawValue,
                actual: actualAccess.rawValue
            )
        }
        let output = try reader.readLengthPrefixed {
            (payloadReader: inout DatabaseWireReader) throws(DatabaseWireError) in
            try Command.Output(from: &payloadReader)
        }
        let commitVersion: UInt64?
        switch Command.access {
        case .readOnly:
            commitVersion = nil
        case .readWrite:
            commitVersion = try reader.readUInt64()
        }
        self.output = output
        self.commitVersion = commitVersion
        self.continuation = try reader.readOptionalBytes()
    }
}

extension DatabaseTypedCommandResponse where Command: DatabaseReadCommandDescriptor {
    public init(
        output: Command.Output,
        continuation: ByteString? = nil
    ) {
        self.output = output
        self.commitVersion = nil
        self.continuation = continuation
    }
}

extension DatabaseTypedCommandResponse where Command: DatabaseWriteCommandDescriptor {
    public init(
        output: Command.Output,
        commitVersion: UInt64,
        continuation: ByteString? = nil
    ) {
        self.output = output
        self.commitVersion = commitVersion
        self.continuation = continuation
    }
}
