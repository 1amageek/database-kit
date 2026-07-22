/// Defines how incoming references are handled when their target is deleted.
public enum DeleteRule: String, Sendable, Codable, Hashable {
    case nullify
    case cascade
    case deny
    case noAction
}
