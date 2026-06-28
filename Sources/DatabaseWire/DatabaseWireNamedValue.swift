/// Wire named field value.
public struct DatabaseWireNamedValue: Sendable, Hashable {
    public let name: String
    public let value: DatabaseWireFieldValue

    public init(name: String, value: DatabaseWireFieldValue) {
        self.name = name
        self.value = value
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(name)
        try value.encode(into: &writer)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.name = try reader.readString()
        self.value = try DatabaseWireFieldValue(from: &reader)
    }
}
