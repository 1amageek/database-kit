/// Stable value representation of an index descriptor for schema catalogs.
///
/// Combines `IndexKindMetadata` with common index options while preserving all
/// information required by runtime index registration and schema inspection.
/// - `name`: Index identifier
/// - `kind`: Index kind metadata
/// - `commonMetadata`: CommonIndexOptions (unique, sparse, storedFieldNames, userMetadata.*)
public struct IndexDescriptorMetadata: Sendable, Hashable, Codable {

    /// Index name (unique identifier)
    public let name: String

    /// Metadata describing the index kind.
    public let kind: IndexKindMetadata

    /// CommonIndexOptions metadata:
    /// - "unique": Bool - Uniqueness constraint
    /// - "sparse": Bool - Sparse index
    /// - "storedFieldNames": [String] - Covering index fields
    /// - "userMetadata.*": User-defined metadata
    public let commonMetadata: [String: IndexMetadataValue]

    // MARK: - Index Descriptor Metadata

    public init(_ descriptor: IndexDescriptor) {
        self.name = descriptor.name
        self.kind = descriptor.kind
        self.commonMetadata = Self.commonMetadata(from: descriptor)
    }

    // MARK: - Stored Metadata

    public init(
        name: String,
        kind: IndexKindMetadata,
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

    private static func commonMetadata(from descriptor: IndexDescriptor) -> [String: IndexMetadataValue] {
        var metadata: [String: IndexMetadataValue] = [:]

        // CommonIndexOptions
        metadata["unique"] = .bool(descriptor.commonOptions.unique)
        metadata["sparse"] = .bool(descriptor.commonOptions.sparse)

        // storedFieldNames
        if !descriptor.storedFieldNames.isEmpty {
            metadata["storedFieldNames"] = .stringArray(descriptor.storedFieldNames)
        }

        // User-defined metadata (with prefix to avoid conflicts)
        for (key, value) in descriptor.commonOptions.metadata {
            metadata["userMetadata.\(key)"] = .string(value)
        }

        return metadata
    }
}
