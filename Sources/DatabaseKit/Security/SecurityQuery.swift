import DatabaseTypes
// SecurityQuery.swift
// Core - Query information for security evaluation


/// Query information for security evaluation
///
/// Used to validate query constraints during list operations.
/// Security rules are not filters - they validate the query itself,
/// not filter the results.
///
/// **Usage**:
/// ```swift
/// extension Post: SecurityPolicy {
///     static func permitsQuery(
///         _ query: SecurityQuery,
///         in context: AuthorizationContext
///     ) -> Bool {
///         // Only allow queries with limit <= 100
///         context.isAuthenticated && (query.limit ?? 0) <= 100
///     }
/// }
/// ```
public struct SecurityQuery: Sendable, Hashable {
    /// Maximum number of items to retrieve
    public let limit: UInt64?

    /// Offset for pagination
    public let offset: UInt64?

    /// Sort order fields
    public let orderBy: [String]?

    public init(
        limit: UInt64? = nil,
        offset: UInt64? = nil,
        orderBy: [String]? = nil
    ) {
        self.limit = limit
        self.offset = offset
        self.orderBy = orderBy
    }
}
