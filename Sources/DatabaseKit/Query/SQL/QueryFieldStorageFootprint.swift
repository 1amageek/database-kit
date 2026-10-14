/// Checked representation counts for the declared field envelope.
/// These counts are not allocator sizes or runtime admission authority.
public struct QueryFieldStorageFootprint: Sendable, Hashable {
    public internal(set) var valueNodes: UInt64 = 0
    public internal(set) var objectEntries: UInt64 = 0
    public internal(set) var arrayElements: UInt64 = 0
    public internal(set) var newUTF8Bytes: UInt64 = 0
    public internal(set) var retainedByteViewCount: UInt64 = 0
    public internal(set) var retainedByteViewLength: UInt64 = 0
    public internal(set) var maximumDepth: UInt64 = 0

    public init() {}
}
