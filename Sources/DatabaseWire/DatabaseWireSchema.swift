/// Wire database schema snapshot.
public struct DatabaseWireSchema: Sendable, Hashable {
    public let entities: [DatabaseWireEntitySchema]

    public init(entities: [DatabaseWireEntitySchema]) {
        self.entities = entities
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeCount(entities.count)
        for entity in entities {
            try entity.encode(into: &writer)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let count = try reader.readCount()
        var entities: [DatabaseWireEntitySchema] = []
        entities.reserveCapacity(count)
        for _ in 0..<count {
            entities.append(try DatabaseWireEntitySchema(from: &reader))
        }
        self.entities = entities
    }
}
