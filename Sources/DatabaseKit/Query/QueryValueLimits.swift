/// Public arbitrary-value limits use conservative per-reference retention.
/// These limits do not confer a runtime allocation reservation.
public struct QueryValueLimits: Sendable, Hashable {
    public let maximumRetainedBytes: UInt64
    public let maximumTotalNodes: UInt64
    public let maximumNestingDepth: UInt64
    public let maximumCollectionElements: UInt64

    public init(maximumRetainedBytes: UInt64, maximumTotalNodes: UInt64,
                maximumNestingDepth: UInt64, maximumCollectionElements: UInt64) {
        self.maximumRetainedBytes = maximumRetainedBytes
        self.maximumTotalNodes = maximumTotalNodes
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumCollectionElements = maximumCollectionElements
    }
}
