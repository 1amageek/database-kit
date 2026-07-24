import DatabaseTypes
/// Stable value representation of an index descriptor for schema catalogs.
///
/// Combines `IndexKindMetadata` with common index options while preserving all
/// information required by runtime index registration and schema inspection.
/// - `name`: Index identifier
/// - `kind`: Index kind metadata
/// - `commonOptions`: Options shared by every index kind
/// - `storedFieldNames`: Fields copied into the index value
public struct IndexDescriptorMetadata: Sendable, Hashable, Codable {

    /// Index name (unique identifier)
    public let name: String

    /// Metadata describing the index kind.
    public let kind: IndexKindMetadata

    /// Options shared by every index kind.
    public let commonOptions: CommonIndexOptions

    /// Fields copied into the index value for covering reads.
    public let storedFieldNames: [String]

    // MARK: - Index Descriptor Metadata

    public init(_ descriptor: IndexDescriptor) {
        self.name = descriptor.name
        self.kind = descriptor.kind
        self.commonOptions = descriptor.commonOptions
        self.storedFieldNames = descriptor.storedFieldNames
    }

    // MARK: - Stored Metadata

    public init(
        name: String,
        kind: IndexKindMetadata,
        commonOptions: CommonIndexOptions = .init(),
        storedFieldNames: [String] = []
    ) {
        self.name = name
        self.kind = kind
        self.commonOptions = commonOptions
        self.storedFieldNames = storedFieldNames
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
        commonOptions.unique
    }

    /// Sparse index flag (convenience accessor)
    public var sparse: Bool {
        commonOptions.sparse
    }
}
