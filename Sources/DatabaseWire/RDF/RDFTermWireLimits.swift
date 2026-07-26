struct RDFTermWireLimits: Sendable, Equatable {
    let maximumBytes: Int
    let maximumDepth: Int
    let maximumObjectCount: Int

    init(
        maximumBytes: Int = 65_536,
        maximumDepth: Int = 32,
        maximumObjectCount: Int = 65_536
    ) throws(RDFTermWireLimitsError) {
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

    init(
        validatedMaximumBytes maximumBytes: Int,
        maximumDepth: Int,
        maximumObjectCount: Int
    ) {
        self.maximumBytes = maximumBytes
        self.maximumDepth = maximumDepth
        self.maximumObjectCount = maximumObjectCount
    }

    static let `default` = Self(
        validatedMaximumBytes: 65_536,
        maximumDepth: 32,
        maximumObjectCount: 65_536
    )
}
