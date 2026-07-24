import DatabaseTypes
import DatabaseValue

public enum CommandReadOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.commandRead
    public typealias Request = DatabaseCommandRequest

    public struct Response: DatabaseWireValue, Hashable {
        public let output: ByteString
        public let continuation: ByteString?

        public init(
            output: ByteString = [],
            continuation: ByteString? = nil
        ) {
            self.output = output
            self.continuation = continuation
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try writer.writeBytes(output)
            try writer.writeOptionalBytes(continuation)
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            self.init(
                output: try reader.readBytes(),
                continuation: try reader.readOptionalBytes()
            )
        }
    }
}
