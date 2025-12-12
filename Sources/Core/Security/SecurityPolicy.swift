// SecurityPolicy.swift
// Core - Security policy protocol for declarative access control

import Foundation

/// Security policy protocol
///
/// Implement per-type to define access control conditions for each operation.
///
/// **Design Principles**:
/// 1. Protocol-based: Implement `SecurityPolicy` per type
/// 2. Declarative: Define permission conditions as functions
/// 3. Separation of concerns: Tenant isolation via Directory + FDB Partition,
///    document-level control via SecurityPolicy
///
/// **Usage**:
/// ```swift
/// extension Post: SecurityPolicy {
///     static func allowGet(resource: Post, auth: (any AuthContext)?) -> Bool {
///         resource.isPublic || resource.authorID == auth?.userID
///     }
///
///     static func allowList(query: SecurityQuery<Post>, auth: (any AuthContext)?) -> Bool {
///         auth != nil && (query.limit ?? 0) <= 100
///     }
///
///     static func allowCreate(newResource: Post, auth: (any AuthContext)?) -> Bool {
///         auth != nil && newResource.authorID == auth?.userID
///     }
///
///     static func allowUpdate(resource: Post, newResource: Post, auth: (any AuthContext)?) -> Bool {
///         resource.authorID == auth?.userID
///             && newResource.authorID == resource.authorID
///     }
///
///     static func allowDelete(resource: Post, auth: (any AuthContext)?) -> Bool {
///         resource.authorID == auth?.userID
///     }
/// }
/// ```
public protocol SecurityPolicy: Persistable {

    /// Permission check for single document retrieval
    ///
    /// - Parameters:
    ///   - resource: The document to retrieve
    ///   - auth: Authentication context (nil = unauthenticated)
    /// - Returns: true if allowed
    static func allowGet(resource: Self, auth: (any AuthContext)?) -> Bool

    /// Permission check for query (list retrieval)
    ///
    /// **Important**: Security rules are not filters.
    /// This validates the query itself, not filters the results.
    ///
    /// - Parameters:
    ///   - query: Query information (limit, offset, etc.)
    ///   - auth: Authentication context (nil = unauthenticated)
    /// - Returns: true if allowed
    static func allowList(query: SecurityQuery<Self>, auth: (any AuthContext)?) -> Bool

    /// Permission check for document creation
    ///
    /// - Parameters:
    ///   - newResource: The document to create
    ///   - auth: Authentication context (nil = unauthenticated)
    /// - Returns: true if allowed
    static func allowCreate(newResource: Self, auth: (any AuthContext)?) -> Bool

    /// Permission check for document update
    ///
    /// - Parameters:
    ///   - resource: The document before update
    ///   - newResource: The document after update
    ///   - auth: Authentication context (nil = unauthenticated)
    /// - Returns: true if allowed
    static func allowUpdate(resource: Self, newResource: Self, auth: (any AuthContext)?) -> Bool

    /// Permission check for document deletion
    ///
    /// - Parameters:
    ///   - resource: The document to delete
    ///   - auth: Authentication context (nil = unauthenticated)
    /// - Returns: true if allowed
    static func allowDelete(resource: Self, auth: (any AuthContext)?) -> Bool

    // MARK: - Type-erased methods (internal use)

    /// Type-erased List evaluation
    ///
    /// Defined as a protocol requirement to allow calling from `any SecurityPolicy.Type`.
    /// Normally you only need to implement `allowList` - this method delegates to it.
    static func _evaluateList(
        limit: Int?,
        offset: Int?,
        orderBy: [String]?,
        auth: (any AuthContext)?
    ) -> Bool

    /// Type-erased Get evaluation
    ///
    /// Defined as a protocol requirement to allow calling from `any SecurityPolicy.Type`.
    /// Casts the resource to Self and delegates to `allowGet`.
    static func _evaluateGet(
        resource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool

    /// Type-erased Create evaluation
    ///
    /// Defined as a protocol requirement to allow calling from `any SecurityPolicy.Type`.
    /// Casts the resource to Self and delegates to `allowCreate`.
    static func _evaluateCreate(
        newResource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool

    /// Type-erased Update evaluation
    ///
    /// Defined as a protocol requirement to allow calling from `any SecurityPolicy.Type`.
    /// Casts resources to Self and delegates to `allowUpdate`.
    static func _evaluateUpdate(
        resource: any Persistable,
        newResource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool

    /// Type-erased Delete evaluation
    ///
    /// Defined as a protocol requirement to allow calling from `any SecurityPolicy.Type`.
    /// Casts the resource to Self and delegates to `allowDelete`.
    static func _evaluateDelete(
        resource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool
}

// MARK: - Default Implementation

public extension SecurityPolicy {
    /// Default: deny all (secure by default)
    static func allowGet(resource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowList(query: SecurityQuery<Self>, auth: (any AuthContext)?) -> Bool { false }
    static func allowCreate(newResource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowUpdate(resource: Self, newResource: Self, auth: (any AuthContext)?) -> Bool { false }
    static func allowDelete(resource: Self, auth: (any AuthContext)?) -> Bool { false }

    /// Default implementation of type-erased method
    ///
    /// Builds SecurityQuery internally and delegates to allowList.
    static func _evaluateList(
        limit: Int?,
        offset: Int?,
        orderBy: [String]?,
        auth: (any AuthContext)?
    ) -> Bool {
        let query = SecurityQuery<Self>(limit: limit, offset: offset, orderBy: orderBy)
        return allowList(query: query, auth: auth)
    }

    /// Default implementation of type-erased Get evaluation
    ///
    /// Casts the resource to Self and delegates to allowGet.
    /// Returns false if cast fails.
    static func _evaluateGet(
        resource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool {
        guard let typedResource = resource as? Self else { return false }
        return allowGet(resource: typedResource, auth: auth)
    }

    /// Default implementation of type-erased Create evaluation
    ///
    /// Casts the resource to Self and delegates to allowCreate.
    /// Returns false if cast fails.
    static func _evaluateCreate(
        newResource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool {
        guard let typedResource = newResource as? Self else { return false }
        return allowCreate(newResource: typedResource, auth: auth)
    }

    /// Default implementation of type-erased Update evaluation
    ///
    /// Casts resources to Self and delegates to allowUpdate.
    /// Returns false if casts fail.
    static func _evaluateUpdate(
        resource: any Persistable,
        newResource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool {
        guard let typedOld = resource as? Self,
              let typedNew = newResource as? Self else { return false }
        return allowUpdate(resource: typedOld, newResource: typedNew, auth: auth)
    }

    /// Default implementation of type-erased Delete evaluation
    ///
    /// Casts the resource to Self and delegates to allowDelete.
    /// Returns false if cast fails.
    static func _evaluateDelete(
        resource: any Persistable,
        auth: (any AuthContext)?
    ) -> Bool {
        guard let typedResource = resource as? Self else { return false }
        return allowDelete(resource: typedResource, auth: auth)
    }
}
