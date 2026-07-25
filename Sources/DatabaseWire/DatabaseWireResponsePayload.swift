import DatabaseTypes

enum DatabaseWireResponsePayload: Sendable, Hashable {
    case success(ByteString)
    case failure(RemoteOperationError)

    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch self {
        case .success(let payload):
            writer.writeUInt8(1)
            try writer.writeBytes(payload)
        case .failure(let error):
            writer.writeUInt8(2)
            try error.encode(into: &writer)
        }
    }

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        switch try reader.readUInt8() {
        case 1:
            self = .success(try reader.readBytes())
        case 2:
            self = .failure(try RemoteOperationError(from: &reader))
        case let tag:
            throw .invalidResultPayload(tag)
        }
    }
}
