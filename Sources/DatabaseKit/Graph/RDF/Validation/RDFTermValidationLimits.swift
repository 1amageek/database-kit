public struct RDFTermValidationLimits: Sendable, Equatable {
    public let maximumDepth: Int
    public let maximumTermCount: Int

    public init(
        maximumDepth: Int = 32,
        maximumTermCount: Int = 65_536
    ) throws(RDFTermValidationLimitsError) {
        guard maximumDepth >= 0 else {
            throw .negativeMaximumDepth(maximumDepth)
        }
        guard maximumTermCount > 0 else {
            throw .nonPositiveMaximumTermCount(maximumTermCount)
        }
        self.maximumDepth = maximumDepth
        self.maximumTermCount = maximumTermCount
    }

    package init(
        validatedMaximumDepth maximumDepth: Int,
        maximumTermCount: Int
    ) {
        self.maximumDepth = maximumDepth
        self.maximumTermCount = maximumTermCount
    }

    public static let `default` = Self(
        validatedMaximumDepth: 32,
        maximumTermCount: 65_536
    )
}

public enum RDFTermValidationLimitsError: Error, Sendable, Equatable {
    case negativeMaximumDepth(Int)
    case nonPositiveMaximumTermCount(Int)
}
