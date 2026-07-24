import DatabaseTypes
/// Stable value representation of an index kind for schema catalogs and runtime dispatch.
///
/// Contains the storage contract and kind-specific metadata required to restore
/// index behavior without retaining a generic model type.
/// - `identifier`: IndexKind.identifier
/// - `subspaceStructure`: IndexKind.subspaceStructure
/// - `fieldNames`: IndexKind.fieldNames
/// - `metadata`: Kind-specific properties (dimensions, metric, strategy, etc.)

public struct IndexKindMetadata: Sendable, Hashable, Codable {

    /// Index kind identifier (e.g., "scalar", "vector", "com.mycompany.bloom_filter")
    public let identifier: String

    /// Subspace structure for index storage
    public let subspaceStructure: SubspaceStructure

    /// Field names for indexed KeyPaths
    public let fieldNames: [String]

    /// Kind-specific metadata:
    /// - Vector: "dimensions", "metric"
    /// - Graph: "fromField", "edgeField", "toField", "graphField", "strategy"
    /// - FullText: "tokenizer", "storePositions", "ngramSize", "minTermLength"
    /// - Spatial: "encoding", "level"
    /// - Rank: "scoreTypeName", "bucketSize"
    /// - etc.
    public let metadata: [String: FieldValue]

    // MARK: - Index Kind Metadata

    public init<Kind: IndexKind>(_ kind: borrowing Kind) {
        self.identifier = Kind.identifier
        self.subspaceStructure = Kind.subspaceStructure
        self.fieldNames = kind.fieldNames
        self.metadata = kind.metadata
    }

    // MARK: - Stored Metadata

    public init(
        identifier: String,
        subspaceStructure: SubspaceStructure,
        fieldNames: [String],
        metadata: [String: FieldValue]
    ) {
        self.identifier = identifier
        self.subspaceStructure = subspaceStructure
        self.fieldNames = fieldNames
        self.metadata = metadata
    }
}
