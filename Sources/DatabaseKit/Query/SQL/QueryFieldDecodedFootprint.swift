/// Prospective logical destination counts, separate from allocator capacities.
public struct QueryFieldDecodedFootprint: Sendable, Hashable {
    public internal(set) var nodeCount: UInt64 = 0
    public internal(set) var collectionElementCount: UInt64 = 0
    public internal(set) var maximumNestingDepth: UInt64 = 0
    public internal(set) var utf8ByteCount: UInt64 = 0
    public internal(set) var jsonbNodeCount: UInt64 = 0
    public internal(set) var jsonbElementIndexCount: UInt64 = 0
    public internal(set) var jsonbMemberCount: UInt64 = 0

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
}
