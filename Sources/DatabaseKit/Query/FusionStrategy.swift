/// Canonical score-combination policy for a Fusion query.
public enum FusionStrategy: Sendable, Equatable, Hashable {
    case reciprocalRank(rankConstant: UInt64 = 60)
    case sum
    case maximum
    case weighted([Double])
}
