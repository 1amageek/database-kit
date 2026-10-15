/// The three SQL truth-test targets; UNKNOWN denotes a NULL Boolean.
public enum TruthValue: Sendable, Equatable, Hashable {
    case `false`
    case `true`
    case unknown
}
