/// Distance metric for wire vector search.
public enum DatabaseWireVectorMetric: UInt8, Sendable, Hashable {
    case cosine = 1
    case euclidean = 2
    case dotProduct = 3

    public func encode(into writer: inout DatabaseWireBinaryWriter) {
        writer.writeUInt8(rawValue)
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        let tag = try reader.readUInt8()
        guard let metric = DatabaseWireVectorMetric(rawValue: tag) else {
            throw DatabaseWireError.unknownVectorMetric(tag)
        }
        self = metric
    }
}
