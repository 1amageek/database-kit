import DatabaseTypes
public enum OperationRetryability: UInt8, Sendable, Hashable {
    case never = 1
    case immediate = 2
    case backoff = 3

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidRetryability(rawValue)
        }
        self = value
    }

    func encode(into writer: inout DatabaseWireWriter) {
        writer.writeUInt8(rawValue)
    }
}
