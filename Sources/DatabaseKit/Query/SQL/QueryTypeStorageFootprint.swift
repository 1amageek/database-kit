public struct QueryTypeStorageFootprint: Sendable, Hashable {
    public let typeNodeCapacity: UInt64
    public let columnCapacity: UInt64
    public let retainedStorageByteCount: UInt64
    public let utf8ByteCount: UInt64
}
