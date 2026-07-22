public import DatabaseValue

public enum CommandWriteOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.commandWrite
    public typealias Request = DatabaseCommandRequest

    public struct Response: DatabaseWireValue, Hashable {
        public let output: DatabaseBytes
        public let commitVersion: UInt64
        public let continuation: DatabaseBytes?

        public init(
            output: DatabaseBytes = [],
            commitVersion: UInt64,
            continuation: DatabaseBytes? = nil
        ) {
            self.output = output
            self.commitVersion = commitVersion
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeBytes(output)
            writer.writeUInt64(commitVersion)
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                output: try reader.readBytes(),
                commitVersion: try reader.readUInt64(),
                continuation: try reader.readOptionalBytes()
            )
        }
    }
}
