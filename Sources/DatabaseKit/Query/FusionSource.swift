/// Canonical staged Fusion access path.
public struct FusionSource: Sendable, Equatable, Hashable {
    public let stages: [FusionStageSource]
    public let strategy: FusionStrategy
    public let identityField: String
    public let scoreAnnotation: String

    public init(
        stages: [FusionStageSource],
        strategy: FusionStrategy = .reciprocalRank(),
        identityField: String = "id",
        scoreAnnotation: String = "fusion.score"
    ) {
        self.stages = stages
        self.strategy = strategy
        self.identityField = identityField
        self.scoreAnnotation = scoreAnnotation
    }
}
