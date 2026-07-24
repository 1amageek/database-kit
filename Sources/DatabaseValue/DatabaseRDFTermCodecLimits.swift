public struct RDFTermCodecLimits: Sendable, Equatable {
    public let maximumBytes: Int
    public let maximumDepth: Int
    public let maximumObjectCount: Int

    public init(
        maximumBytes: Int = 65_536,
        maximumDepth: Int = 32,
        maximumObjectCount: Int = 65_536
    ) {
        precondition(maximumBytes >= 0)
        precondition(maximumDepth >= 0)
        precondition(maximumObjectCount > 0)
        self.maximumBytes = maximumBytes
        self.maximumDepth = maximumDepth
        self.maximumObjectCount = maximumObjectCount
    }

    public static let `default` = Self()
}
