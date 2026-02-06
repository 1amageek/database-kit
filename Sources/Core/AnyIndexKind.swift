/// AnyIndexKind - Type-erased IndexKind
///
/// Contains IndexKind protocol requirements and kind-specific metadata.
/// - `identifier`: IndexKind.identifier
/// - `subspaceStructure`: IndexKind.subspaceStructure
/// - `fieldNames`: IndexKind.fieldNames
/// - `metadata`: Kind-specific properties (dimensions, metric, strategy, etc.)

import Foundation

public struct AnyIndexKind: Sendable, Hashable, Codable {

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
    public let metadata: [String: IndexMetadataValue]

    // MARK: - Init from IndexKind

    public init(_ kind: any IndexKind) {
        self.identifier = type(of: kind).identifier
        self.subspaceStructure = type(of: kind).subspaceStructure
        self.fieldNames = kind.fieldNames
        self.metadata = Self.extractMetadata(from: kind)
    }

    // MARK: - Init for Codable reconstruction

    public init(
        identifier: String,
        subspaceStructure: SubspaceStructure,
        fieldNames: [String],
        metadata: [String: IndexMetadataValue]
    ) {
        self.identifier = identifier
        self.subspaceStructure = subspaceStructure
        self.fieldNames = fieldNames
        self.metadata = metadata
    }

    // MARK: - Metadata Extraction

    private static func extractMetadata(from kind: any IndexKind) -> [String: IndexMetadataValue] {
        do {
            let data = try JSONEncoder().encode(kind)
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let dict = jsonObject as? [String: Any] else { return [:] }
            // Filter out fieldNames (already a direct property)
            return dict.compactMapValues { IndexMetadataValue(from: $0) }
                .filter { $0.key != "fieldNames" }
        } catch {
            return [:]
        }
    }
}
