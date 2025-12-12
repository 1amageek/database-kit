// SecurityQuery.swift
// Core - Query information for security evaluation

import Foundation

/// Query information for security evaluation
///
/// Used to validate query constraints during list operations.
/// Security rules are not filters - they validate the query itself,
/// not filter the results.
///
/// **Usage**:
/// ```swift
/// extension Post: SecurityPolicy {
///     static func allowList(query: SecurityQuery<Post>, auth: (any AuthContext)?) -> Bool {
///         // Only allow queries with limit <= 100
///         auth != nil && (query.limit ?? 0) <= 100
///     }
/// }
/// ```
public struct SecurityQuery<T: Persistable>: Sendable {
    /// Maximum number of items to retrieve
    public let limit: Int?

    /// Offset for pagination
    public let offset: Int?

    /// Sort order fields
    public let orderBy: [String]?

    public init(limit: Int? = nil, offset: Int? = nil, orderBy: [String]? = nil) {
        self.limit = limit
        self.offset = offset
        self.orderBy = orderBy
    }
}
