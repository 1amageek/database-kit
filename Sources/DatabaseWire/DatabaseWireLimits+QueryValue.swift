import DatabaseKit

extension DatabaseWireLimits {
    var queryValueLimits: QueryValueLimits {
        QueryValueLimits(
            maximumRetainedBytes: UInt64(maximumFrameBytes),
            maximumTotalNodes: UInt64(maximumObjectCount),
            maximumNestingDepth: UInt64(maximumNestingDepth),
            maximumCollectionElements: UInt64(maximumObjectCount)
        )
    }
}

extension DatabaseWireWriter {
    var queryValueLimits: QueryValueLimits { limits.queryValueLimits }
}
