import DatabaseTypes

/// The authenticated state supplied to an authorization decision.
///
/// This is a concrete value so policy declarations remain usable in Embedded
/// builds without protocol existential storage.
public enum AuthorizationContext: Sendable, Hashable {
    case anonymous
    case authenticated(Principal)

    public var principal: Principal? {
        switch self {
        case .anonymous:
            return nil
        case .authenticated(let principal):
            return principal
        }
    }

    public var isAuthenticated: Bool {
        principal != nil
    }
}
