/// Prospective logical destination counts, separate from allocator capacities.
public struct QueryFieldDecodedFootprint: Sendable, Hashable {
    public internal(set) var nodeCount: UInt64 = 0
    public internal(set) var collectionElementCount: UInt64 = 0
    public internal(set) var maximumNestingDepth: UInt64 = 0
    public internal(set) var utf8ByteCount: UInt64 = 0
    public internal(set) var jsonbNodeCount: UInt64 = 0
    public internal(set) var jsonbElementIndexCount: UInt64 = 0
    public internal(set) var jsonbMemberCount: UInt64 = 0
    public internal(set) var queryValueNodeCount: UInt64 = 0
    public internal(set) var queryValueChildIndexCount: UInt64 = 0
    public internal(set) var queryValueDimensionCount: UInt64 = 0
    public internal(set) var queryTypeNodeCount: UInt64 = 0

    public init() {}

    /// The layout minimum for these logical counts, not a capacity forecast.
    public var minimumJSONBStorageByteCount: UInt64 {
        get throws(QueryValueError) {
            try QueryJSONBStorageFootprint.storageByteCount(
                nodeCapacity: jsonbNodeCount, elementIndexCapacity: jsonbElementIndexCount,
                memberCapacity: jsonbMemberCount
            )
        }
    }

    /// Flat SQL array value and scalar descriptor buffers, excluding scalar leaves.
    public var minimumQueryValueStorageByteCount: UInt64 {
        get throws(QueryValueError) {
            guard queryValueNodeCount != 0 else { return 0 }
            var bytes = UInt64(MemoryLayout<[QueryValueStorage.Record]>.stride
                + MemoryLayout<[Int]>.stride + MemoryLayout<[QueryArrayDimension]>.stride
                + MemoryLayout<[QueryTypeStorage.Record]>.stride + MemoryLayout<[QueryTypeStorage.Column]>.stride)
            for (count, stride) in [
                (queryValueNodeCount, MemoryLayout<QueryValueStorage.Record>.stride),
                (queryValueChildIndexCount, MemoryLayout<Int>.stride),
                (queryValueDimensionCount, MemoryLayout<QueryArrayDimension>.stride),
                (queryTypeNodeCount, MemoryLayout<QueryTypeStorage.Record>.stride),
            ] {
                bytes = try QueryValueAccounting.add(bytes, QueryValueAccounting.multiply(count, UInt64(stride)))
            }
            return bytes
        }
    }
}
