/// Whether truncation preserves or restarts owned sequences.
public enum SQLTruncateIdentity: Sendable, Equatable, Hashable {
    case `continue`
    case restart
}
