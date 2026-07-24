import DatabaseTypes
enum DatabaseWireMessageKind: UInt8 {
    case request = 1
    case response = 2

    init(from reader: inout DatabaseWireReader) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let value = Self(rawValue: rawValue) else {
            throw .invalidMessageKind(rawValue)
        }
        self = value
    }
}
