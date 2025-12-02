// VectorIndexKind.swift
// VectorIndexModel - Vector index metadata (FDB-independent, iOS-compatible)
//
// Defines metadata for vector similarity search indexes. This file is FDB-independent
// and can be used on all platforms including iOS clients.

import Foundation
import Core

/// Vector metric for distance calculation
///
/// **Distance Metrics**:
/// - `.cosine`: Cosine distance (1 - cosine_similarity), range [0, 2]
/// - `.euclidean`: L2 (Euclidean) distance, range [0, ∞)
/// - `.dotProduct`: Negative dot product, range (-∞, ∞)
public enum VectorMetric: String, Sendable, Codable, Hashable {
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
///     var id: String = ULID().ulidString
///
///     // Model definition: Only specify data structure (dimensions, metric)
///     #Index<Product>(
///         [\.embedding],
///         type: VectorIndexKind(
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
    /// Identifier: "vector"
    public static var identifier: String { "vector" }

    /// Subspace structure: hierarchical (HNSW graph, IVF clusters)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field name for the vector field
    public let fieldNames: [String]

    /// Vector dimensions (e.g., 384 for MiniLM, 768 for BERT, 1536 for OpenAI)
    public let dimensions: Int

    /// Distance metric
    public let metric: VectorMetric

    /// Default index name: "{TypeName}_vector_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_vector_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// **Model-level configuration**: Only data structure properties
    /// - embedding: KeyPath to the vector field
    /// - dimensions: Vector size (must match embedding model)
    /// - metric: Distance calculation method
    ///
    /// **Not included here**: Algorithm selection (flatScan/HNSW/IVF)
    /// - Algorithm is runtime configuration (via AlgorithmConfiguration)
    ///
    /// - Parameters:
    ///   - embedding: KeyPath to the vector field
    ///   - dimensions: Vector dimensions (must be positive)
    ///   - metric: Distance metric (default: cosine)
    public init(embedding: PartialKeyPath<Root>, dimensions: Int, metric: VectorMetric = .cosine) {
        precondition(dimensions > 0, "Vector dimensions must be positive")
        self.fieldNames = [Root.fieldName(for: embedding)]
        self.dimensions = dimensions
        self.metric = metric
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String], dimensions: Int, metric: VectorMetric = .cosine) {
        precondition(dimensions > 0, "Vector dimensions must be positive")
        self.fieldNames = fieldNames
        self.dimensions = dimensions
        self.metric = metric
    }

    /// Type validation
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count == 1 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 1,
                actual: types.count
            )
        }
        // Vector field should be array type - validated at runtime when extracting
    }
}

// MARK: - Hashable Conformance

extension VectorIndexKind {
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
