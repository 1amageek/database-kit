/// Top-level wire database operations shared by clients and runtimes.
public enum DatabaseWireOperation: UInt8, Sendable, Hashable {
    case applySchema = 1
    case putRecord = 2
    case getRecord = 3
    case query = 4

    public func encode(into writer: inout DatabaseWireBinaryWriter) {
        writer.writeUInt8(rawValue)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        guard let operation = DatabaseWireOperation(rawValue: tag) else {
            throw DatabaseWireError.unknownOperation(tag)
        }
        self = operation
    }
}
