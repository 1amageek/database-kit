import DatabaseTypes
// SecurityPolicy.swift
// Core - Security policy protocol for declarative access control


/// Security policy protocol
///
/// Implement per-type to define access control conditions for each operation.
///
/// **Design Principles**:
/// 1. Protocol-based: Implement `SecurityPolicy` per type
/// 2. Declarative: Define permission conditions as functions
/// 3. Separation of concerns: Tenant isolation via directory partitioning,
///    document-level control via SecurityPolicy
///
/// **Usage**:
/// ```swift
/// extension Post: SecurityPolicy {
///     static func permitsRead(
///         of resource: Post,
///         in context: AuthorizationContext
///     ) -> Bool {
///         resource.isPublic
///             || resource.authorID == context.principal?.identifier
///     }
///
///     static func permitsQuery(
///         _ query: SecurityQuery,
///         in context: AuthorizationContext
///     ) -> Bool {
///         context.isAuthenticated && (query.limit ?? 0) <= 100
///     }
///
///     static func permitsCreate(
///         _ newResource: Post,
///         in context: AuthorizationContext
///     ) -> Bool {
///         newResource.authorID == context.principal?.identifier
///     }
///
///     static func permitsUpdate(
///         from resource: Post,
///         to newResource: Post,
///         in context: AuthorizationContext
///     ) -> Bool {
///         resource.authorID == context.principal?.identifier
///             && newResource.authorID == resource.authorID
///     }
///
///     static func permitsDelete(
///         _ resource: Post,
///         in context: AuthorizationContext
///     ) -> Bool {
///         resource.authorID == context.principal?.identifier
///     }
/// }
/// ```
public protocol SecurityPolicy: Persistable {

    /// Permission check for single document retrieval
    ///
    /// - Parameters:
    ///   - resource: The document to retrieve
    ///   - context: Request authorization context.
    /// - Returns: true if allowed
    static func permitsRead(
        of resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool

    /// Permission check for query (list retrieval)
    ///
    /// **Important**: Security rules are not filters.
    /// This validates the query itself, not filters the results.
    ///
    /// - Parameters:
    ///   - query: Query information (limit, offset, etc.)
    ///   - context: Request authorization context.
    /// - Returns: true if allowed
    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool

    /// Permission check for document creation
    ///
    /// - Parameters:
    ///   - newResource: The document to create
    ///   - context: Request authorization context.
    /// - Returns: true if allowed
    static func permitsCreate(
        _ newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool

    /// Permission check for document update
    ///
    /// - Parameters:
    ///   - resource: The document before update
    ///   - newResource: The document after update
    ///   - context: Request authorization context.
    /// - Returns: true if allowed
    static func permitsUpdate(
        from resource: borrowing Self,
        to newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool

    /// Permission check for document deletion
    ///
    /// - Parameters:
    ///   - resource: The document to delete
    ///   - context: Request authorization context.
    /// - Returns: true if allowed
    static func permitsDelete(
        _ resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool
}

// MARK: - Default Implementation

public extension SecurityPolicy {
    /// Default: deny all (secure by default)
    static func permitsRead(
        of resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { false }

    static func permitsQuery(
        _ query: borrowing SecurityQuery,
        in context: borrowing AuthorizationContext
    ) -> Bool { false }

    static func permitsCreate(
        _ newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { false }

    static func permitsUpdate(
        from resource: borrowing Self,
        to newResource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { false }

    static func permitsDelete(
        _ resource: borrowing Self,
        in context: borrowing AuthorizationContext
    ) -> Bool { false }
}
