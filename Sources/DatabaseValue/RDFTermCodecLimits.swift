public struct RDFTermCodecLimits: Sendable, Equatable {
    public let maximumBytes: Int
    public let maximumDepth: Int
    public let maximumObjectCount: Int

    public init(
        maximumBytes: Int = 65_536,
        maximumDepth: Int = 32,
        maximumObjectCount: Int = 65_536
    ) throws(RDFTermCodecLimitsError) {
        guard maximumBytes >= 0 else {
            throw .negativeMaximumBytes(maximumBytes)
        }
        guard maximumDepth >= 0 else {
            throw .negativeMaximumDepth(maximumDepth)
        }
        guard maximumObjectCount > 0 else {
            throw .nonPositiveMaximumObjectCount(maximumObjectCount)
        }
        self.maximumBytes = maximumBytes
        self.maximumDepth = maximumDepth
        self.maximumObjectCount = maximumObjectCount
    }

    package init(
        validatedMaximumBytes maximumBytes: Int,
        maximumDepth: Int,
        maximumObjectCount: Int
    ) {
        self.maximumBytes = maximumBytes
        self.maximumDepth = maximumDepth
        self.maximumObjectCount = maximumObjectCount
    }

    public static let `default` = Self(
        validatedMaximumBytes: 65_536,
        maximumDepth: 32,
        maximumObjectCount: 65_536
    )
}
