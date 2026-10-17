/// Semantic sequence administration within an admitted SQL request.
public enum SQLSequenceCommand: Sendable, Hashable {
    case create(SQLSequence)
    case alter(SQLSequence, restart: Int64?)
    case drop(id: String, cascade: Bool)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.create(let left), .create(let right)): return left == right
        case (.alter(let left, let lr), .alter(let right, let rr)): return left == right && lr == rr
        case (.drop(let left, let lc), .drop(let right, let rc)):
            return SQLIdentifier(value: left) == SQLIdentifier(value: right) && lc == rc
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .create(let sequence): hasher.combine(0); hasher.combine(sequence)
        case .alter(let sequence, let restart): hasher.combine(1); hasher.combine(sequence); hasher.combine(restart)
        case .drop(let id, let cascade): hasher.combine(2); hasher.combine(SQLIdentifier(value: id)); hasher.combine(cascade)
        }
    }
}
