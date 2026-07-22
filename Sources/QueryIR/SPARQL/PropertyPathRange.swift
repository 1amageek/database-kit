/// Validated repetition bounds for an extended SPARQL property path.
public struct PropertyPathRange: Sendable, Equatable, Hashable {
    public let minimum: Int
    public let maximum: Int?

    public init(
        minimum: Int,
        maximum: Int?
    ) throws(PropertyPathRangeError) {
        guard minimum >= 0 else {
            throw .negativeMinimum(minimum)
        }
        if let maximum {
            guard maximum >= 0 else {
                throw .negativeMaximum(maximum)
            }
            guard maximum >= minimum else {
                throw .maximumBelowMinimum(
                    minimum: minimum,
                    maximum: maximum
                )
            }
        }
        self.minimum = minimum
        self.maximum = maximum
    }
}
