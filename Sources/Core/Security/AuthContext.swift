// AuthContext.swift
// Core - Authentication context protocol for security evaluation

import Foundation

/// Authentication context protocol
///
/// Applications define their own authentication type conforming to this protocol.
///
/// **Trust Model**:
/// DatabaseEngine does not validate the Auth.
/// Auth is assumed to be constructed from a validated token at the application layer.
///
/// **Minimum Requirements**:
/// - `userID`: Required. User identifier
/// - `roles`: Optional. Defaults to empty set (affects Admin judgment)
///
/// **Usage**:
/// ```swift
/// // Minimal implementation (roles defaults to empty set)
/// struct SimpleAuth: AuthContext {
///     let userID: String
/// }
///
/// // Role-based implementation
/// struct MyAuth: AuthContext {
///     let userID: String
///     let roles: Set<String>
///     let teamIDs: [String]
/// }
/// ```
public protocol AuthContext: Sendable {
    /// User identifier (required)
    var userID: String { get }

    /// Role set (used for Admin judgment)
    ///
    /// Default implementation returns empty set.
    /// Implement explicitly if Admin judgment is needed.
    var roles: Set<String> { get }
}

public extension AuthContext {
    /// Default: empty roles (not judged as Admin)
    var roles: Set<String> { [] }
}
