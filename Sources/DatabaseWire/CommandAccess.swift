import DatabaseTypes

/// The transaction access required to execute a database command.
public enum CommandAccess: UInt8, DatabaseWireValue, Hashable {
    case readOnly = 0
    case readWrite = 1

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(rawValue)
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let access = Self(rawValue: rawValue) else {
            throw .invalidCommandAccess(rawValue)
        }
        self = access
    }
}
