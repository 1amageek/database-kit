/// Wire entity schema.
public struct DatabaseWireEntitySchema: Sendable, Hashable {
    public let typeName: String
    public let version: UInt32
    public let fields: [DatabaseWireFieldSchema]
    public let indexes: [DatabaseWireIndexDescriptor]

    public init(
        typeName: String,
        version: UInt32,
        fields: [DatabaseWireFieldSchema],
        indexes: [DatabaseWireIndexDescriptor]
    ) {
        self.typeName = typeName
        self.version = version
        self.fields = fields
        self.indexes = indexes
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(typeName)
        writer.writeUInt32(version)
        try writer.writeCount(fields.count)
        for field in fields {
            try field.encode(into: &writer)
        }
        try writer.writeCount(indexes.count)
        for index in indexes {
            try index.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.typeName = try reader.readString()
        self.version = try reader.readUInt32()
        let fieldCount = try reader.readCount()
        var fields: [DatabaseWireFieldSchema] = []
        fields.reserveCapacity(fieldCount)
        for _ in 0..<fieldCount {
            fields.append(try DatabaseWireFieldSchema(from: &reader))
        }
        self.fields = fields

        let indexCount = try reader.readCount()
        var indexes: [DatabaseWireIndexDescriptor] = []
        indexes.reserveCapacity(indexCount)
        for _ in 0..<indexCount {
            indexes.append(try DatabaseWireIndexDescriptor(from: &reader))
        }
        self.indexes = indexes
    }
}
