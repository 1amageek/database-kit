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
        try value.encode(into: &writer)
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
        self.init(
            position: position,
            name: name,
            value: try FieldValue(from: &reader)
        )
    }
}
