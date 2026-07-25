import DatabaseTypes
// CommonIndexOptions.swift
// Shared index configuration options.
//
// Common options that apply to all index kinds.

/// Common configuration options shared across all index kinds.
///
/// These options apply regardless of the specific IndexKind:
/// - `.scalar`, `.vector`, `.spatial`, `.rank`, etc.
///
/// **Example**:
/// ```swift
/// let options = CommonIndexOptions(
///     unique: true,
///     sparse: false
/// )
/// ```
public struct CommonIndexOptions: Sendable, Hashable {
    /// Whether the index enforces uniqueness of indexed values.
    ///
    /// - `true`: Index values must be unique across all entities
    /// - `false`: Multiple entities can share the same index value (default)
    ///
    /// **Example**:
    /// ```swift
    /// // Email index with uniqueness constraint
    /// #Index(
    ///     .scalar,
    ///     fields: [\User.email],
    ///     unique: true
    /// )
    /// ```
    public let unique: Bool

    /// Whether the index is sparse (omits null/nil values).
    ///
    /// - `true`: Only non-null values are indexed (saves space)
    /// - `false`: All values are indexed, including nulls (default)
    ///
    /// **Note**: This is declarative metadata. The execution layer determines
    /// how to omit null values while preserving transaction semantics.
    public let sparse: Bool

    /// Optional user-defined metadata for application-specific use.
    ///
    /// This field allows storing custom metadata alongside index
    /// descriptors without modifying the protocol.
    ///
    /// **Example**:
    /// ```swift
    /// let options = CommonIndexOptions(
    ///     metadata: ["category": "user_index", "version": "1.0"]
    /// )
    /// ```
    public let metadata: [String: String]

    /// Initialize common index options.
    ///
    /// - Parameters:
    ///   - unique: Uniqueness constraint (default: false)
    ///   - sparse: Sparse index (default: false)
    ///   - metadata: Custom metadata (default: empty)
    public init(
        unique: Bool = false,
        sparse: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.unique = unique
        self.sparse = sparse
        self.metadata = metadata
    }
}
