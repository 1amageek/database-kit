/// Candidate-set requirement for a Fusion input.
public enum FusionInputRequirement: UInt8, Sendable, Equatable, Hashable {
    case unrestricted
    case candidates
}
