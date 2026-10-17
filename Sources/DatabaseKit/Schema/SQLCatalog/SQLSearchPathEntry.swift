/// A deferred search-path declaration; current-user expansion is runtime-owned.
public enum SQLSearchPathEntry: Sendable, Hashable {
    case schema(String)
    case currentUser

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.currentUser, .currentUser):
            return true
        case (.schema(let left), .schema(let right)):
            return SQLIdentifier(value: left) == SQLIdentifier(value: right)
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .schema(let name):
            hasher.combine(0)
            hasher.combine(SQLIdentifier(value: name))
        case .currentUser:
            hasher.combine(1)
        }
    }
}
