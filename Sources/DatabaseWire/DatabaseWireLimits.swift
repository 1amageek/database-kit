import DatabaseTypes
public struct DatabaseWireLimits: Sendable, Hashable {
    /// The largest recursive value depth that the owned Swift value model can
    /// release safely on every supported runtime stack.
    public static let maximumSupportedNestingDepth = 1_024

    public let maximumFrameBytes: Int
    public let maximumStringBytes: Int
    public let maximumByteStringBytes: Int
    public let maximumCollectionCount: Int
    public let maximumNestingDepth: Int
    public let maximumObjectCount: Int

    public init(
        maximumFrameBytes: Int,
        maximumStringBytes: Int,
        maximumByteStringBytes: Int,
        maximumCollectionCount: Int,
        maximumNestingDepth: Int,
        maximumObjectCount: Int
    ) throws(DatabaseWireLimitsError) {
        let values: [(DatabaseWireLimit, Int)] = [
            (.frameBytes, maximumFrameBytes),
            (.stringBytes, maximumStringBytes),
            (.byteStringBytes, maximumByteStringBytes),
            (.collectionElements, maximumCollectionCount),
            (.nestingDepth, maximumNestingDepth),
            (.objects, maximumObjectCount),
        ]
        if let (limit, value) = values.first(where: { $0.1 < 0 }) {
            throw .negativeValue(limit: limit, value: value)
        }
        guard maximumNestingDepth <= Self.maximumSupportedNestingDepth else {
            throw .nestingDepthExceedsSupportedMaximum(
                actual: maximumNestingDepth,
                maximum: Self.maximumSupportedNestingDepth
            )
        }

        self.maximumFrameBytes = maximumFrameBytes
        self.maximumStringBytes = maximumStringBytes
        self.maximumByteStringBytes = maximumByteStringBytes
        self.maximumCollectionCount = maximumCollectionCount
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumObjectCount = maximumObjectCount
    }

    public static let `default`: DatabaseWireLimits = {
        do {
            return try DatabaseWireLimits(
                maximumFrameBytes: 4 * 1_024 * 1_024,
                maximumStringBytes: 1 * 1_024 * 1_024,
                maximumByteStringBytes: 4 * 1_024 * 1_024,
                maximumCollectionCount: 100_000,
                maximumNestingDepth: 64,
                maximumObjectCount: 250_000
            )
        } catch {
            preconditionFailure("The canonical database wire limits are invalid")
        }
    }()
}
