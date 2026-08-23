/// Direction of a numeric score signal.
public enum FusionScoreOrder: UInt8, Sendable, Equatable, Hashable {
    case higherIsBetter
    case lowerIsBetter
}

/// Interpretation of the ordering or annotations returned by a Fusion input.
public enum FusionScoring: Sendable, Equatable, Hashable {
    case position
    case annotation(name: String, order: FusionScoreOrder)
}
