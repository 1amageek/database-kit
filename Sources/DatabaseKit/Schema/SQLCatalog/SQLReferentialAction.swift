/// The referential transition following a referenced-key change.
public enum SQLReferentialAction: Sendable, Hashable {
    case noAction
    case restrict
    case cascade
    case setNull
    case setDefault
}
