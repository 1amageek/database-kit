public struct DatabaseWireQueryRequest: Sendable, Hashable {
    public let typeName: String
    public let predicate: DatabaseWirePredicate?
    public let limit: UInt32

    public init(typeName: String, predicate: DatabaseWirePredicate?, limit: UInt32) {
        self.typeName = typeName
        self.predicate = predicate
        self.limit = limit
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(typeName)
        if let predicate {
            writer.writeBool(true)
            try predicate.encode(into: &writer)
        } else {
            writer.writeBool(false)
        }
        writer.writeUInt32(limit)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.typeName = try reader.readString()
        if try reader.readBool() {
            self.predicate = try DatabaseWirePredicate(from: &reader)
        } else {
            self.predicate = nil
        }
        self.limit = try reader.readUInt32()
    }
}
