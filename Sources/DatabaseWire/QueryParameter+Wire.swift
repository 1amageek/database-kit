import DatabaseTypes
import DatabaseKit

extension QueryParameter {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard position > 0 else {
            throw .invalidParameterPosition(position)
        }
        if let name, name.isEmpty {
            throw .emptyParameterName
        }
        writer.writeUInt32(position)
        try writer.writeOptionalString(name)
        writer.writeBool(type != nil)
        if let type { try QueryColumnTypeWireCodec.encode(type, into: &writer) }
        if let type, !QueryValueValidator.accepts(value, type: type) {
            throw .invalidQueryValue(.incompatibleType)
        }
        try QueryValueWireCodec.encode(value, into: &writer)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let position = try reader.readUInt32()
        guard position > 0 else {
            throw .invalidParameterPosition(position)
        }
        let name = try reader.readOptionalString()
        if let name, name.isEmpty {
            throw .emptyParameterName
        }
        let type = try reader.readBool()
            ? try QueryColumnTypeWireCodec.decode(from: &reader) : nil
        let value = try QueryValueWireCodec.decode(from: &reader)
        if let type, !QueryValueValidator.accepts(value, type: type) {
            throw .invalidQueryValue(.incompatibleType)
        }
        self.init(
            position: position,
            name: name,
            value: value,
            type: type
        )
    }
}
