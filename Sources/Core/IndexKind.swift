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
/// - Type-safe validation (using Any.Type)
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
///     public static func validateTypes(_ types: [Any.Type]) throws {
///         for type in types {
///             guard TypeValidation.isComparable(type) else {
///                 throw IndexTypeValidationError.unsupportedType(...)
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
///     public static func validateTypes(_ types: [Any.Type]) throws {
///         // Custom validation logic
///     }
///
///     public init(falsePositiveRate: Double, expectedCapacity: Int) {
///         self.falsePositiveRate = falsePositiveRate
///         self.expectedCapacity = expectedCapacity
///     }
/// }
/// ```
public protocol IndexKind: Sendable, Codable, Hashable {
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

    /// Field names used by this index
    ///
    /// Stored as strings for Codable compatibility.
    /// Order matters for composite indexes.
    var fieldNames: [String] { get }

    /// Canonical, Foundation-free metadata consumed after the concrete generic
    /// index kind crosses a schema or runtime boundary.
    ///
    /// Implementations must include every configuration value that changes
    /// storage layout, maintenance, or query behavior. Field names are carried
    /// separately by `fieldNames` and must not be duplicated here.
    var metadata: [String: FieldValue] { get }

    /// Validate whether this index kind supports specified types
    ///
    /// **Parameters**:
    /// - types: Types of indexed fields (array order corresponds to fieldNames)
    ///
    /// **Throws**: IndexTypeValidationError if type not supported
    static func validateTypes(_ types: [Any.Type]) throws
}

extension IndexKind {
    public var metadata: [String: FieldValue] { [:] }
}

/// Index type validation error
///
/// **Example**:
/// ```swift
/// throw IndexTypeValidationError.unsupportedType(
///     index: "vector",
///     type: String.self,
///     reason: "Vector index requires array types"
/// )
/// ```
public enum IndexTypeValidationError: Error, CustomStringConvertible {
    /// Unsupported type
    ///
    /// - Parameters:
    ///   - index: Index kind identifier
    ///   - type: Unsupported type
    ///   - reason: Error reason (user-facing message)
    case unsupportedType(index: String, type: Any.Type, reason: String)

    /// Invalid field count
    ///
    /// - Parameters:
    ///   - index: Index kind identifier
    ///   - expected: Expected field count
    ///   - actual: Actual field count
    case invalidTypeCount(index: String, expected: Int, actual: Int)

    /// Custom validation failed
    ///
    /// - Parameters:
    ///   - index: Index kind identifier
    ///   - reason: Failure reason (user-facing message)
    case customValidationFailed(index: String, reason: String)

    public var description: String {
        switch self {
        case let .unsupportedType(index, type, reason):
            return "Index '\(index)' does not support type '\(type)': \(reason)"

        case let .invalidTypeCount(index, expected, actual):
            return "Index '\(index)' expects \(expected) field(s), but got \(actual)"

        case let .customValidationFailed(index, reason):
            return "Index '\(index)' validation failed: \(reason)"
        }
    }
}
