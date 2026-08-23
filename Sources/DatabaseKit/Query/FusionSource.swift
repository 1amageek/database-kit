/// Canonical staged Fusion access path.
public struct FusionSource: Sendable, Equatable, Hashable {
    public let stages: [FusionStageSource]
    public let strategy: FusionStrategy

    public init(
        stages: [FusionStageSource],
        strategy: FusionStrategy = .reciprocalRank()
    ) {
        self.stages = stages
        self.strategy = strategy
    }
}
