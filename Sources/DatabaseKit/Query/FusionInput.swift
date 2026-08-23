/// One canonical operation in a Fusion stage.
public struct FusionInput: Sendable, Equatable, Hashable {
    public let operation: FusionInputOperation
    public let scoring: FusionScoring?
    public let requirement: FusionInputRequirement
    public let limit: UInt64?

    public init(
        operation: FusionInputOperation,
        scoring: FusionScoring? = nil,
        requirement: FusionInputRequirement = .unrestricted,
        limit: UInt64? = nil
    ) {
        self.operation = operation
        self.scoring = scoring
        self.requirement = requirement
        self.limit = limit
    }
}
