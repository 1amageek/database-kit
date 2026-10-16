public struct QueryValueStorageFootprint: Sendable, Hashable {
    public let nodeCapacity: UInt64
    public let childIndexCapacity: UInt64
    public let dimensionCapacity: UInt64
    public let retainedStorageByteCount: UInt64
    public let utf8ByteCount: UInt64
    public let leafRetainedByteCount: UInt64
    public let typeStorageFootprint: QueryTypeStorageFootprint

    var retainedByteCount: UInt64 {
        get throws(QueryValueError) {
            try QueryValueAccounting.add(
                QueryValueAccounting.add(retainedStorageByteCount, leafRetainedByteCount),
                QueryValueAccounting.add(typeStorageFootprint.retainedStorageByteCount,
                                         typeStorageFootprint.utf8ByteCount))
        }
    }
}
