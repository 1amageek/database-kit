// VectorIndexKind.swift
// Vector index declaration metadata.

import DatabaseTypes

/// Vector metric for distance calculation
///
/// **Distance Metrics**:
/// - `.cosine`: Cosine distance (1 - cosine_similarity), range [0, 2]
/// - `.euclidean`: L2 (Euclidean) distance, range [0, ∞)
/// - `.dotProduct`: Negative dot product, range (-∞, ∞)
public enum VectorMetric: String, Sendable, Hashable {
    /// Cosine distance: 1 - cosine_similarity
    /// Best for: Normalized vectors, text embeddings
    case cosine

    /// L2 (Euclidean) distance: sqrt(sum((a-b)^2))
    /// Best for: Spatial data, unnormalized vectors
    case euclidean

    /// Inner product distance: -dot_product
    /// Best for: Dot product similarity, maximum inner product search
    case dotProduct
}

/// Vector index kind for similarity search
///
/// **Purpose**: K-nearest neighbor search for high-dimensional vectors
/// - Single vector field per index
/// - Multiple distance metrics (cosine, euclidean, dotProduct)
/// - Runtime algorithm selection (flatScan, HNSW, IVF)
///
/// **Index Structure** (depends on algorithm):
/// - **Flat Scan**: `[indexSubspace][primaryKey] = vector`
/// - **HNSW**: Hierarchical graph structure with metadata
/// - **IVF**: Inverted file with cluster centroids
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Product {
///     var id: String
///
///     // Model definition: Only specify data structure (dimensions, metric)
///     #Index(
///         VectorIndexKind<Product>(
///             embedding: \.embedding,
///             dimensions: 384,
///             metric: .cosine
///         )
///     )
///
///     var embedding: [Float]
/// }
/// ```
///
/// **Design Principle**: Separation of concerns
/// - Model defines **what** to index (dimensions, metric)
/// - Runtime selects **how** to index (algorithm: flat/HNSW/IVF via AlgorithmConfiguration)
public struct VectorIndexKind<Root: Persistable>: IndexKind {
    public typealias Model = Root

    /// Identifier: "vector"
    public static var identifier: String { "vector" }

    /// Subspace structure: hierarchical (HNSW graph, IVF clusters)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field name for the vector field
    public let indexFields: [IndexField<Root>]

    /// Vector dimensions (e.g., 384 for MiniLM, 768 for BERT, 1536 for OpenAI)
    public let dimensions: Int

    /// Distance metric
    public let metric: VectorMetric

    /// Default index name: "{TypeName}_vector_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        return "\(Root.persistableType)_vector_\(flattenedNames.joined(separator: "_"))"
    }

    public init(
        embedding: IndexField<Root>,
        dimensions: Int,
        metric: VectorMetric = .cosine
    ) {
        self.indexFields = [embedding]
        self.dimensions = dimensions
        self.metric = metric
    }

    package init(
        canonicalFields: [IndexFieldMetadata],
        dimensions: Int,
        metric: VectorMetric = .cosine
    ) {
        self.indexFields = canonicalFields.map {
            IndexField<Root>(metadata: $0)
        }
        self.dimensions = dimensions
        self.metric = metric
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard dimensions > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Vector dimensions must be positive"
            )
        }
    }

    /// Persisted field validation
    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count == 1 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        guard let field = fields.first else { return }
        guard field.type == .vector, !field.isArray else {
            throw .unsupportedField(
                index: identifier,
                field: field,
                reason: "Vector index fields must use the canonical Vector primitive"
            )
        }
    }
}

// MARK: - Hashable Conformance

extension VectorIndexKind {
    public var metadata: [String: FieldValue] {
        [
            "dimensions": .int64(Int64(dimensions)),
            "metric": .string(metric.rawValue),
        ]
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(dimensions)
        hasher.combine(metric)
    }

    public static func == (lhs: VectorIndexKind, rhs: VectorIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames && lhs.dimensions == rhs.dimensions && lhs.metric == rhs.metric
    }
}
