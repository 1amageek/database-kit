/// The closed SQL pattern operator family. ERE operators do not accept ESCAPE.
public enum PatternMatchKind: Sendable, Equatable, Hashable {
    case like
    case caseInsensitiveLike
    case similarTo
    case regularExpression
    case caseInsensitiveRegularExpression

    public var permitsEscape: Bool {
        switch self {
        case .like, .caseInsensitiveLike, .similarTo: return true
        case .regularExpression, .caseInsensitiveRegularExpression: return false
        }
    }
}
