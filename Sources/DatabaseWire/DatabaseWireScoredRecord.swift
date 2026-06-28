/// Record returned by ranked wire queries.
public struct DatabaseWireScoredRecord: Sendable, Hashable {
    public let record: DatabaseWireRecord
    public let distance: Double

    public init(record: DatabaseWireRecord, distance: Double) {
        self.record = record
        self.distance = distance
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try record.encode(into: &writer)
        writer.writeDouble(distance)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.record = try DatabaseWireRecord(from: &reader)
        self.distance = try reader.readDouble()
    }
}
