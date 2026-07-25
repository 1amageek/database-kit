import DatabaseTypes
// FieldAccessLevel.swift
// Core - Field-level access control


/// Field access level for field-level security
///
/// Defines who can access a field. Used with `@Restricted` property wrapper.
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Employee {
///     var name: String = ""
///
///     @Restricted(read: .roles(["hr", "manager"]), write: .roles(["hr"]))
///     var salary: Double = 0
///
///     @Restricted(read: .authenticated)
///     var internalNotes: String = ""
/// }
/// ```
public enum FieldAccessLevel: Sendable, Equatable, Hashable {
    /// Everyone can access (no restriction)
    case `public`

    /// Only authenticated users can access
    case authenticated

    /// Only users with specific roles can access
    case roles(Set<String>)

    /// Evaluate access for the given authorization context.
    ///
    /// - Parameter context: The request authorization context.
    /// - Returns: true if access is allowed
    public func allows(_ context: AuthorizationContext) -> Bool {
        switch self {
        case .public:
            return true

        case .authenticated:
            return context.isAuthenticated

        case .roles(let required):
            guard let principal = context.principal else {
                return false
            }
            return !principal.roles.isDisjoint(with: required)

        }
    }
}

// MARK: - CustomStringConvertible

extension FieldAccessLevel: CustomStringConvertible {
    public var description: String {
        switch self {
        case .public:
            return ".public"
        case .authenticated:
            return ".authenticated"
        case .roles(let roles):
            return ".roles(\(roles.sorted()))"
        }
    }
}
