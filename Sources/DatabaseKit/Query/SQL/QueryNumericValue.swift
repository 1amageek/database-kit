import DatabaseTypes

public struct QueryNumericValue: Sendable, Hashable {
    public let value: ExactDecimal
    public let displayScale: Int32

    public init(value: ExactDecimal, displayScale: Int32) throws(QueryValueError) {
        guard (0...16383).contains(displayScale),
              value.coefficient == 0 || displayScale >= max(0, value.scale) else {
            throw .invalidNumericDisplayScale(displayScale)
        }
        var magnitude = value.coefficient.magnitude
        var digits = 1
        while magnitude >= 10 { magnitude /= 10; digits += 1 }
        guard digits <= 38 else { throw .numericOutOfRange }
        self.value = value
        self.displayScale = displayScale
    }
}
