/// AnyIndexDescriptor - Type-erased IndexDescriptor for catalog persistence
///
/// **Design Principles**:
/// 1. Separate IndexKind (AnyIndexKind) from IndexDescriptor (AnyIndexDescriptor)
/// 2. IndexKind-specific metadata in AnyIndexKind
/// 3. CommonIndexOptions metadata in AnyIndexDescriptor
/// 4. Adding new IndexKind types requires no changes (Open-Closed Principle)
///
/// **Usage**:
/// - TypeCatalog stores `[AnyIndexDescriptor]` for index metadata
/// - SchemaRegistry persists TypeCatalog as JSON (requires Codable)
/// - CLI uses AnyIndexDescriptor to inspect index configurations

import Foundation

/// Type-erased IndexDescriptor
///
/// Combines AnyIndexKind with CommonIndexOptions metadata.
/// - `name`: Index identifier
/// - `kind`: Type-erased IndexKind
/// - `commonMetadata`: CommonIndexOptions (unique, sparse, storedFieldNames, userMetadata.*)
///
/// Replaces the previous `IndexCatalog` struct with a unified representation
/// that preserves full type information from `IndexDescriptor`.
public struct AnyIndexDescriptor: Sendable, Hashable, Codable {

    /// Index name (unique identifier)
    public let name: String

    /// Type-erased IndexKind
    public let kind: AnyIndexKind

    /// CommonIndexOptions metadata:
    /// - "unique": Bool - Uniqueness constraint
    /// - "sparse": Bool - Sparse index
    /// - "storedFieldNames": [String] - Covering index fields
    /// - "userMetadata.*": User-defined metadata
    public let commonMetadata: [String: IndexMetadataValue]

    // MARK: - Init from IndexDescriptor

    public init(_ descriptor: IndexDescriptor) {
        self.name = descriptor.name
        self.kind = AnyIndexKind(descriptor.kind)
        self.commonMetadata = Self.extractCommonMetadata(from: descriptor)
    }

    // MARK: - Init for Codable reconstruction

    public init(
        name: String,
        kind: AnyIndexKind,
        commonMetadata: [String: IndexMetadataValue]
    ) {
        self.name = name
        self.kind = kind
        self.commonMetadata = commonMetadata
    }

    // MARK: - Convenience Accessors (Kind shortcuts)

    /// Index kind identifier (shortcut for kind.identifier)
    public var kindIdentifier: String {
        kind.identifier
    }

    /// Field names (shortcut for kind.fieldNames)
    public var fieldNames: [String] {
        kind.fieldNames
    }

    /// Subspace structure (shortcut for kind.subspaceStructure)
    public var subspaceStructure: SubspaceStructure {
        kind.subspaceStructure
    }

    // MARK: - Convenience Accessors (CommonOptions)

    /// Uniqueness constraint (convenience accessor)
    public var unique: Bool {
        commonMetadata["unique"]?.boolValue ?? false
    }

    /// Sparse index flag (convenience accessor)
    public var sparse: Bool {
        commonMetadata["sparse"]?.boolValue ?? false
    }

    /// Stored field names for covering index (convenience accessor)
    public var storedFieldNames: [String] {
        commonMetadata["storedFieldNames"]?.stringArrayValue ?? []
    }

    // MARK: - Metadata Extraction

    private static func extractCommonMetadata(from descriptor: IndexDescriptor) -> [String: IndexMetadataValue] {
        var result: [String: IndexMetadataValue] = [:]

        // CommonIndexOptions
        result["unique"] = .bool(descriptor.commonOptions.unique)
        result["sparse"] = .bool(descriptor.commonOptions.sparse)

        // storedFieldNames
        if !descriptor.storedFieldNames.isEmpty {
            result["storedFieldNames"] = .stringArray(descriptor.storedFieldNames)
        }

        // User-defined metadata (with prefix to avoid conflicts)
        for (key, value) in descriptor.commonOptions.metadata {
            if let converted = IndexMetadataValue(from: value) {
                result["userMetadata.\(key)"] = converted
            }
        }

        return result
    }
}
