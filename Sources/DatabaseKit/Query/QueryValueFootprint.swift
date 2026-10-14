/// Conservative representation counts, not unique physical allocation.
/// Each byte reference charges its known retained capacity, including aliases.
public struct QueryValueFootprint: Sendable, Hashable {
    public let nodeCount: UInt64
    public let collectionElementCount: UInt64
    public let retainedByteCount: UInt64
    public let maximumNestingDepth: UInt64

    public init(nodeCount: UInt64, collectionElementCount: UInt64,
                retainedByteCount: UInt64, maximumNestingDepth: UInt64) {
        self.nodeCount = nodeCount
        self.collectionElementCount = collectionElementCount
        self.retainedByteCount = retainedByteCount
        self.maximumNestingDepth = maximumNestingDepth
    }

    public func validate(limits: QueryValueLimits) throws(QueryValueError) {
        for (resource, actual, maximum) in [
            ("retainedBytes", retainedByteCount, limits.maximumRetainedBytes),
            ("nodes", nodeCount, limits.maximumTotalNodes),
            ("depth", maximumNestingDepth, limits.maximumNestingDepth),
            ("collectionElements", collectionElementCount, limits.maximumCollectionElements),
        ] where actual > maximum {
            throw .resourceLimit(resource: resource, actual: actual, maximum: maximum)
        }
    }
}
