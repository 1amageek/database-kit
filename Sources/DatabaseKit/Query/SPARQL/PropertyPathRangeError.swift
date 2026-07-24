public enum PropertyPathRangeError: Error, Sendable, Equatable {
    case negativeMinimum(Int)
    case negativeMaximum(Int)
    case maximumBelowMinimum(minimum: Int, maximum: Int)
}
