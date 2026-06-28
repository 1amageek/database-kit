/// Wire record row keyed by field name.
public struct DatabaseWireRecord: Sendable, Hashable {
    public let typeName: String
    public let id: String
    public let fields: [DatabaseWireNamedValue]

    public init(typeName: String, id: String, fields: [DatabaseWireNamedValue]) {
        self.typeName = typeName
        self.id = id
        self.fields = fields
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(typeName)
        try writer.writeString(id)
        try writer.writeCount(fields.count)
        for field in fields {
            try field.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.typeName = try reader.readString()
        self.id = try reader.readString()
        let count = try reader.readCount()
        var fields: [DatabaseWireNamedValue] = []
        fields.reserveCapacity(count)
        for _ in 0..<count {
            fields.append(try DatabaseWireNamedValue(from: &reader))
        }
        self.fields = fields
    }
}
