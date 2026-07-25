import DatabaseTypes
// IndexConfiguration.swift
// Core - Protocol for defining runtime index configuration
//
// Provides runtime configuration for indexes that need heavy parameters
// (HNSW, full-text search, etc.) separate from compile-time IndexKind metadata.

/// Protocol for defining runtime index configuration
///
/// **Purpose**: Separate heavy, environment-dependent parameters from IndexKind.
/// While IndexKind is defined in model macros, IndexConfiguration is specified
/// at Container initialization time.
///
/// **Design Principles**:
/// - No associated type: enables `[any IndexConfiguration]` without wrapping
/// - Concrete initializers resolve typed key paths through compiled schema metadata
/// - The stored contract contains only semantic, Sendable values
/// - Multiple configurations per index supported (e.g., multi-language full-text)
///
/// **When to use IndexConfiguration**:
/// - Memory-intensive parameters (HNSW: M, efConstruction, efSearch)
/// - Environment-dependent settings (vector dimensions, language settings)
/// - Parameters that vary between deployments
///
/// **When NOT to use** (use IndexKind properties instead):
/// - Lightweight declaration metadata such as version retention strategy
/// - Compile-time constants
/// - Index behavior that doesn't vary between deployments
///
/// **Example - Vector Index**:
/// ```swift
/// public struct VectorIndexConfiguration<Model: Persistable>: IndexConfiguration {
///     public static var kindIdentifier: String { "vector" }
///
///     public let fieldName: String
///     public var modelTypeName: String { String(describing: Model.self) }
///
///     public let dimensions: Int
///     public let hnswParameters: HNSWParameters
/// }
/// ```
///
/// **Example - Full-text Index (multiple languages)**:
/// ```swift
/// DBConfiguration(
///     indexConfigurations: [
///         FullTextIndexConfiguration<Article>(keyPath: \.content, language: "ja", ...),
///         FullTextIndexConfiguration<Article>(keyPath: \.content, language: "en", ...)
///     ]
/// )
/// ```
public protocol IndexConfiguration: Sendable {
    /// Identifier of the corresponding IndexKind
    ///
    /// Must match the `identifier` property of the IndexKind this configuration applies to.
    ///
    /// **Examples**:
    /// - "vector" for `.vector`
    /// - "fulltext" for `.fullText`
    /// - "com.mycompany.custom" for custom IndexKinds
    static var kindIdentifier: String { get }

    /// Canonical target field name from the model's compiled schema.
    ///
    /// Concrete initializers accept a typed key path and resolve it immediately.
    /// Runtime configuration does not retain key paths or infer names from their
    /// debug representation.
    var fieldName: String { get }

    /// Target model's type name
    ///
    /// Used for generating index name: `{modelTypeName}_{fieldName}`
    var modelTypeName: String { get }

    /// Computed index name
    ///
    /// Format: `{modelTypeName}_{fieldName}`
    var indexName: String { get }

    /// Optional subspace key for data isolation
    ///
    /// When multiple configurations exist for the same index (e.g., multi-language full-text),
    /// this key creates separate subspaces for each configuration's data.
    ///
    /// **Subspace Structure**:
    /// - Without subspaceKey: `[indexSubspace]/[indexName]/...`
    /// - With subspaceKey: `[indexSubspace]/[indexName]/[subspaceKey]/...`
    ///
    /// **Use Cases**:
    /// - Multi-language full-text: `subspaceKey: "ja"`, `subspaceKey: "en"`
    /// - Multiple algorithms: `subspaceKey: "hnsw"`, `subspaceKey: "flat"`
    /// - Tenant isolation: `subspaceKey: tenantId`
    ///
    /// Default implementation returns `nil` (no subspace separation).
    var subspaceKey: String? { get }
}

// MARK: - Default Implementation

extension IndexConfiguration {
    /// Computed index name
    public var indexName: String {
        return "\(modelTypeName)_\(fieldName)"
    }

    /// Default subspace key (nil = no subspace separation)
    public var subspaceKey: String? { nil }
}

// MARK: - Configuration Errors

/// Errors that occur during index configuration validation
public enum IndexConfigurationError: Error, CustomStringConvertible, Sendable {
    /// The specified index was not found in the schema
    case unknownIndex(indexName: String)

    /// The IndexConfiguration's kindIdentifier doesn't match the IndexKind
    case indexKindMismatch(indexName: String, expected: String, actual: String)

    /// Duplicate configuration for the same index (when duplicates are not allowed)
    case duplicateConfiguration(indexName: String)

    /// Configuration is missing for a required index
    case missingRequiredConfiguration(indexName: String, kindIdentifier: String)

    /// Invalid configuration parameters
    case invalidConfiguration(indexName: String, reason: String)

    public var description: String {
        switch self {
        case let .unknownIndex(indexName):
            return "Index configuration references unknown index '\(indexName)'"

        case let .indexKindMismatch(indexName, expected, actual):
            return "Index '\(indexName)' has kind '\(expected)', but configuration has kindIdentifier '\(actual)'"

        case let .duplicateConfiguration(indexName):
            return "Multiple configurations provided for index '\(indexName)' where only one is allowed"

        case let .missingRequiredConfiguration(indexName, kindIdentifier):
            return "Index '\(indexName)' of kind '\(kindIdentifier)' requires runtime configuration"

        case let .invalidConfiguration(indexName, reason):
            return "Invalid configuration for index '\(indexName)': \(reason)"
        }
    }
}
