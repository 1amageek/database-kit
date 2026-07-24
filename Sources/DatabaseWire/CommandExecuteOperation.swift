import DatabaseTypes
import DatabaseValue

public enum CommandExecuteOperation: DatabaseOperation {
    public static let identifier = DatabaseOperationIdentifier.commandExecute
    public typealias Request = DatabaseCommandRequest

    public enum Response: DatabaseWireValue, Hashable {
        case read(
            output: ByteString,
            continuation: ByteString?
        )
        case write(
            output: ByteString,
            commitVersion: UInt64,
            continuation: ByteString?
        )

        public var access: DatabaseCommandAccess {
            switch self {
            case .read:
                return .readOnly
            case .write:
                return .readWrite
            }
        }

        public func encode(
            into writer: inout DatabaseWireWriter
        ) throws(DatabaseWireError) {
            try access.encode(into: &writer)
            switch self {
            case .read(let output, let continuation):
                try writer.writeBytes(output)
                try writer.writeOptionalBytes(continuation)
            case .write(let output, let commitVersion, let continuation):
                try writer.writeBytes(output)
                writer.writeUInt64(commitVersion)
                try writer.writeOptionalBytes(continuation)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try DatabaseCommandAccess(from: &reader) {
            case .readOnly:
                self = .read(
                    output: try reader.readBytes(),
                    continuation: try reader.readOptionalBytes()
                )
            case .readWrite:
                self = .write(
                    output: try reader.readBytes(),
                    commitVersion: try reader.readUInt64(),
                    continuation: try reader.readOptionalBytes()
                )
            }
        }
    }
}
