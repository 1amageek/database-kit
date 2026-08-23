/// Canonical operation performed by one Fusion input.
public enum FusionInputOperation: Sendable, Equatable, Hashable {
    case index(FusionIndexSource)
    case connected(FusionConnectedSource)
    case filter(Expression)
    case order([SortKey])
}
