import DatabaseTypes
public enum DatabaseRetryability: UInt8, Sendable, Hashable {
    case never = 1
    case immediate = 2
    case backoff = 3

    public init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidRetryability(rawValue)
        }
        self = value
    }

    public func encode(into writer: inout DatabaseWireWriter) {
        writer.writeUInt8(rawValue)
    }
}
