import DatabaseKit

extension CommandAccess: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt8(rawValue)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let rawValue = try reader.readUInt8()
        guard let access = Self(rawValue: rawValue) else {
            throw .invalidCommandAccess(rawValue)
        }
        self = access
    }
}
