/// Retained flat buffers and string content, separate from logical tree size.
public struct QueryJSONBStorageFootprint: Sendable, Hashable {
    public let nodeCapacity: UInt64
    public let elementIndexCapacity: UInt64
    public let memberCapacity: UInt64
    public let retainedStorageByteCount: UInt64
    /// UTF-8 content count; this is not the physical capacity of String storage.
    public let utf8ByteCount: UInt64

    /// Byte size for explicitly selected capacities, without allocating buffers.
    /// Counts alone do not predict the capacities selected by Swift Array growth.
    public static func storageByteCount(nodeCapacity: UInt64, elementIndexCapacity: UInt64,
                                        memberCapacity: UInt64) throws(QueryValueError) -> UInt64 {
        var bytes: UInt64 = 0
        for (capacity, stride) in [
            (nodeCapacity, UInt64(MemoryLayout<QueryJSONBStorage.Record>.stride)),
            (elementIndexCapacity, UInt64(MemoryLayout<Int>.stride)),
            (memberCapacity, UInt64(MemoryLayout<QueryJSONBStorage.Member>.stride)),
        ] {
            let product = capacity.multipliedReportingOverflow(by: stride)
            let sum = bytes.addingReportingOverflow(product.partialValue)
            guard !product.overflow, !sum.overflow else { throw .arithmeticOverflow }
            bytes = sum.partialValue
        }
        return bytes
    }

    init(nodeCapacity: UInt64, elementIndexCapacity: UInt64, memberCapacity: UInt64,
         retainedStorageByteCount: UInt64, utf8ByteCount: UInt64) {
        self.nodeCapacity = nodeCapacity
        self.elementIndexCapacity = elementIndexCapacity
        self.memberCapacity = memberCapacity
        self.retainedStorageByteCount = retainedStorageByteCount
        self.utf8ByteCount = utf8ByteCount
    }
}
