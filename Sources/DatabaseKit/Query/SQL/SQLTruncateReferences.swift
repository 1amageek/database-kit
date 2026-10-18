/// Whether referencing relations must be explicit or are added transitively.
public enum SQLTruncateReferences: Sendable, Equatable, Hashable {
    case restrict
    case cascade
}
