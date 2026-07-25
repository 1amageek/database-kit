/// One stable column declaration in a query row page.
public struct QueryColumn: Sendable, Hashable {
    public let number: UInt32
    public let name: String

    public init(number: UInt32, name: String) {
        self.number = number
        self.name = name
    }

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt32(number)
        try writer.writeString(name)
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            number: try reader.readUInt32(),
            name: try reader.readString()
        )
    }
}
