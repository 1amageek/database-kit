import DatabaseKit

enum QueryColumnTypeWireCodec {
    static func encode(
        _ type: QueryColumnType, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else {
            throw .invalidQueryValue(.incompatibleType)
        }
        switch type {
        case .primitive(let type, let isArray):
            writer.writeUInt8(0)
            try writer.writeString(type.rawValue)
            writer.writeBool(isArray)
        case .sql(let type):
            writer.writeUInt8(1)
            try QueryIRDataTypeWireCodec.encode(type, into: &writer)
        }
    }

    static func decode(from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryColumnType {
        try reader.beginQueryPayload()
        defer { reader.endQueryPayload() }
        let type: QueryColumnType
        switch try reader.readUInt8() {
        case 0:
            let rawType = try reader.readString()
            guard let primitive = FieldSchemaType(rawValue: rawType) else {
                throw .invalidQueryValue(.incompatibleType)
            }
            type = .primitive(primitive, isArray: try reader.readBool())
        case 1:
            type = .sql(try QueryIRDataTypeWireCodec.decode(from: &reader))
        case let tag:
            throw .invalidValueTag(tag)
        }
        guard QueryValueValidator.accepts(.primitive(.null), type: type) else {
            throw .invalidQueryValue(.incompatibleType)
        }
        return type
    }
}
