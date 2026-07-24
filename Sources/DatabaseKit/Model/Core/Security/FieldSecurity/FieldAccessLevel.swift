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

    /// Evaluate access for the given auth context
    ///
    /// - Parameter auth: The authentication context (nil = unauthenticated)
    /// - Returns: true if access is allowed
    public func evaluate(auth: (any AuthContext)?) -> Bool {
        switch self {
        case .public:
            return true

        case .authenticated:
            return auth != nil

        case .roles(let required):
            guard let auth = auth else { return false }
            return !auth.roles.isDisjoint(with: required)

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
