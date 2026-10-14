import DatabaseKit

extension QueryColumn {
    func encode(into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        writer.writeUInt32(number)
        try writer.writeString(name)
        try QueryColumnTypeWireCodec.encode(type, into: &writer)
        writer.writeBool(isNullable)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        let number = try reader.readUInt32()
        let name = try reader.readString()
        let type = try QueryColumnTypeWireCodec.decode(from: &reader)
        let isNullable = try reader.readBool()
        do throws(QueryValueError) {
            try self.init(number: number, name: name, type: type, isNullable: isNullable)
        } catch {
            throw .invalidQueryValue(error)
        }
    }
}
