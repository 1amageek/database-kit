/// Wire field schema metadata.
public struct DatabaseWireFieldSchema: Sendable, Hashable {
    public let name: String
    public let type: DatabaseWireFieldType
    public let isOptional: Bool
    public let fieldNumber: UInt32

    public init(name: String, type: DatabaseWireFieldType, isOptional: Bool, fieldNumber: UInt32) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.fieldNumber = fieldNumber
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(name)
        type.encode(into: &writer)
        writer.writeBool(isOptional)
        writer.writeUInt32(fieldNumber)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.name = try reader.readString()
        self.type = try DatabaseWireFieldType(from: &reader)
        self.isOptional = try reader.readBool()
        self.fieldNumber = try reader.readUInt32()
    }
}
