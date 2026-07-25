import DatabaseKit
import DatabaseTypes

public enum CommandExecuteOperation: DatabaseOperationDeclaration {
    public static let identifier = DatabaseOperationIdentifier.commandExecute
    public typealias Request = CommandRequest

    public enum Response: DatabaseWireValue, Hashable {
        case read(
            output: FieldValue,
            continuation: ByteString?
        )
        case write(
            output: FieldValue,
            commitVersion: UInt64,
            continuation: ByteString?
        )

        public var access: CommandAccess {
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
                try output.encode(into: &writer)
                try writer.writeOptionalBytes(continuation)
            case .write(let output, let commitVersion, let continuation):
                try output.encode(into: &writer)
                writer.writeUInt64(commitVersion)
                try writer.writeOptionalBytes(continuation)
            }
        }

        public init(
            from reader: inout DatabaseWireReader
        ) throws(DatabaseWireError) {
            switch try CommandAccess(from: &reader) {
            case .readOnly:
                self = .read(
                    output: try FieldValue(from: &reader),
                    continuation: try reader.readOptionalBytes()
                )
            case .readWrite:
                self = .write(
                    output: try FieldValue(from: &reader),
                    commitVersion: try reader.readUInt64(),
                    continuation: try reader.readOptionalBytes()
                )
            }
        }
    }
}
