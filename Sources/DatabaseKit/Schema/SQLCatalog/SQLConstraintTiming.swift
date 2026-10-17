/// A constraint's permitted request-transaction checking schedule.
public enum SQLConstraintTiming: Sendable, Hashable {
    case immediate
    case deferrable(initiallyDeferred: Bool)
}
