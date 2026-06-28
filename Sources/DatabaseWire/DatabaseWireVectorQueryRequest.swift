/// Wire request for exact vector nearest-neighbor search.
public struct DatabaseWireVectorQueryRequest: Sendable, Hashable {
    public let typeName: String
    public let fieldName: String
    public let dimensions: UInt32
    public let metric: DatabaseWireVectorMetric
    public let queryVector: [Double]
    public let k: UInt32
    public let predicate: DatabaseWirePredicate?

    public init(
        typeName: String,
        fieldName: String,
        dimensions: UInt32,
        metric: DatabaseWireVectorMetric,
        queryVector: [Double],
        k: UInt32,
        predicate: DatabaseWirePredicate? = nil
    ) {
        self.typeName = typeName
        self.fieldName = fieldName
        self.dimensions = dimensions
        self.metric = metric
        self.queryVector = queryVector
        self.k = k
        self.predicate = predicate
    }

    public func encode(into writer: inout DatabaseWireBinaryWriter) throws(DatabaseWireError) {
        try writer.writeString(typeName)
        try writer.writeString(fieldName)
        writer.writeUInt32(dimensions)
        metric.encode(into: &writer)
        try writer.writeCount(queryVector.count)
        for value in queryVector {
            writer.writeDouble(value)
        }
        writer.writeUInt32(k)
        if let predicate {
            writer.writeBool(true)
            try predicate.encode(into: &writer)
        } else {
            writer.writeBool(false)
        }
    }

    public init(from reader: inout DatabaseWireBinaryReader) throws(DatabaseWireError) {
        self.typeName = try reader.readString()
        self.fieldName = try reader.readString()
        self.dimensions = try reader.readUInt32()
        self.metric = try DatabaseWireVectorMetric(from: &reader)
        let vectorCount = try reader.readCount()
        var vector: [Double] = []
        vector.reserveCapacity(vectorCount)
        for _ in 0..<vectorCount {
            vector.append(try reader.readDouble())
        }
        self.queryVector = vector
        self.k = try reader.readUInt32()
        if try reader.readBool() {
            self.predicate = try DatabaseWirePredicate(from: &reader)
        } else {
            self.predicate = nil
        }
    }
}
