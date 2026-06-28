/// Wire index descriptor.
public struct DatabaseWireIndexDescriptor: Sendable, Hashable {
    public let name: String
    public let kind: DatabaseWireIndexKind
    public let fields: [String]
    public let unique: Bool

    public init(name: String, kind: DatabaseWireIndexKind, fields: [String], unique: Bool = false) {
        self.name = name
        self.kind = kind
        self.fields = fields
        self.unique = unique
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(name)
        try kind.encode(into: &writer)
        try writer.writeCount(fields.count)
        for field in fields {
            try writer.writeString(field)
        }
        writer.writeBool(unique)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.name = try reader.readString()
        self.kind = try DatabaseWireIndexKind(from: &reader)
        let count = try reader.readCount()
        var fields: [String] = []
        fields.reserveCapacity(count)
        for _ in 0..<count {
            fields.append(try reader.readString())
        }
        self.fields = fields
        self.unique = try reader.readBool()
    }
}
