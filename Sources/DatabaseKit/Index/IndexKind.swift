import DatabaseTypes
// IndexKind.swift
// Protocol for defining index kind metadata.
//
// Extension point allowing third parties to define custom index kinds.
// New kinds can be added without modifying the declaration core.
//
// **Note**: This is the metadata-only base protocol. Runtime maintainers are
// registered by database-framework.

/// Protocol for defining index kinds
///
/// **Extensibility**: Third parties can define custom kinds
/// - No database-framework modification is required for the declaration itself
/// - New kinds added via protocol implementation only
///
/// **Naming convention**:
/// - Built-in: Lowercase words ("scalar", "count", "vector")
/// - Extended: Reverse DNS format ("com.mycompany.bloom_filter")
///
/// **Design principles**:
/// - Static validation through canonical field schemas
/// - Structure declaration (SubspaceStructure)
/// - Separation of implementation (no execution logic)
///
/// **Example**:
/// ```swift
/// // Built-in kind
/// public struct ScalarIndexKind: IndexKind {
///     public static let identifier = "scalar"
///     public static let subspaceStructure = SubspaceStructure.flat
///
///     public static func validateFields(_ fields: [FieldSchema]) throws {
///         for field in fields {
///             guard field.supportsOrderedIndex else {
///                 throw IndexValidationError.unsupportedField(...)
///             }
///         }
///     }
///
///     public init() {}
/// }
///
/// // Third-party kind (in third-party package)
/// public struct BloomFilterIndexKind: IndexKind {
///     public static let identifier = "com.mycompany.bloom_filter"
///     public static let subspaceStructure = SubspaceStructure.flat
///
///     public let falsePositiveRate: Double
///     public let expectedCapacity: Int
///
///     public static func validateFields(_ fields: [FieldSchema]) throws {
///         // Custom validation logic
///     }
///
///     public init(falsePositiveRate: Double, expectedCapacity: Int) {
///         self.falsePositiveRate = falsePositiveRate
///         self.expectedCapacity = expectedCapacity
///     }
/// }
/// ```
public protocol IndexKind: Sendable, Hashable {
    associatedtype Model: Persistable

    /// Unique identifier for this kind
    ///
    /// **Naming convention**:
    /// - Built-in kinds: Lowercase words ("scalar", "count", "vector")
    /// - Extended kinds: Reverse DNS format ("com.mycompany.bloom_filter")
    ///
    /// **Examples**:
    /// - "scalar" (built-in)
    /// - "vector" (extended declaration)
    /// - "com.mycompany.bloom_filter" (third-party)
    ///
    /// **Note**: This identifier is used in IndexKind's type erasure mechanism.
    /// No two kinds may share the same identifier.
    static var identifier: String { get }

    /// Subspace structure type
    ///
    /// **Purpose**: Execution layer determines Subspace creation strategy
    /// - `.flat`: Simple key structure [value][pk]
    /// - `.hierarchical`: Complex hierarchy (consider DirectoryLayer)
    /// - `.aggregation`: Store aggregated value directly [groupKey] → value
    ///
    /// **Note**: DirectoryLayer usage decision is delegated to execution layer
    static var subspaceStructure: SubspaceStructure { get }

    /// Default index name for this kind
    ///
    /// Generated from the type name and field names.
    /// Can be overridden by specifying `name:` parameter in #Index macro.
    ///
    /// **Examples**:
    /// - ScalarIndexKind: "Product_category_price"
    /// - CountIndexKind: "Order_count_status"
    /// - VectorIndexKind: "Document_vector_embedding"
    var indexName: String { get }

    /// Model-scoped fields selected by this index.
    ///
    /// Order is part of the persisted key contract.
    var indexFields: [IndexField<Model>] { get }

    /// Canonical, Foundation-free metadata consumed after the concrete generic
    /// index kind crosses a schema or runtime boundary.
    ///
    /// Implementations must include every configuration value that changes
    /// storage layout, maintenance, or query behavior. Field names are carried
    /// separately by `fieldNames` and must not be duplicated here.
    var metadata: [String: FieldValue] { get }

    /// Validate whether this index kind supports the selected persisted fields.
    ///
    /// **Parameters**:
    /// - fields: Canonical field schemas in the same order as `fieldNames`
    ///
    /// **Throws**: `IndexValidationError` when a field contract is unsupported
    static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError)

    /// Validate configuration values that are independent of field types.
    ///
    /// `IndexDescriptor` evaluates this contract when it captures a concrete
    /// index declaration. `Schema` then rejects any captured failure before
    /// exposing the catalog to a runtime.
    func validateConfiguration() throws(IndexValidationError)
}

extension IndexKind {
    public var fieldNames: [String] {
        indexFields.map { $0.name }
    }

    public var metadata: [String: FieldValue] { [:] }

    public func validateConfiguration() throws(IndexValidationError) {}
}
