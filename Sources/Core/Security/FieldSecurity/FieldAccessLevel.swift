// FieldAccessLevel.swift
// Core - Field-level access control

import Foundation

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
public enum FieldAccessLevel: Sendable {
    /// Everyone can access (no restriction)
    case `public`

    /// Only authenticated users can access
    case authenticated

    /// Only users with specific roles can access
    case roles(Set<String>)

    /// Custom access rule
    case custom(@Sendable (any AuthContext) -> Bool)

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

        case .custom(let predicate):
            guard let auth = auth else { return false }
            return predicate(auth)
        }
    }
}

// MARK: - Equatable (partial)

extension FieldAccessLevel: Equatable {
    public static func == (lhs: FieldAccessLevel, rhs: FieldAccessLevel) -> Bool {
        switch (lhs, rhs) {
        case (.public, .public):
            return true
        case (.authenticated, .authenticated):
            return true
        case (.roles(let l), .roles(let r)):
            return l == r
        case (.custom, .custom):
            // Custom closures cannot be compared
            return false
        default:
            return false
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
        case .custom:
            return ".custom(...)"
        }
    }
}
