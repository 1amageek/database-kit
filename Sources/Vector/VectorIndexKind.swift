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
public struct VectorIndexKind: IndexKind {
    /// Identifier: "vector"
    public static let identifier = "vector"

    /// Subspace structure: hierarchical (HNSW graph, IVF clusters)
    public static let subspaceStructure = SubspaceStructure.hierarchical

    /// Vector dimensions (e.g., 384 for MiniLM, 768 for BERT, 1536 for OpenAI)
    public let dimensions: Int

    /// Distance metric
    public let metric: VectorMetric

    /// Initialize vector index kind
    ///
    /// **Model-level configuration**: Only data structure properties
    /// - dimensions: Vector size (must match embedding model)
    /// - metric: Distance calculation method
    ///
    /// **Not included here**: Algorithm selection (flatScan/HNSW/IVF)
    /// - Algorithm is runtime configuration (via AlgorithmConfiguration)
    ///
    /// - Parameters:
    ///   - dimensions: Vector dimensions (must be positive)
    ///   - metric: Distance metric (default: cosine)
    public init(dimensions: Int, metric: VectorMetric = .cosine) {
        precondition(dimensions > 0, "Vector dimensions must be positive")
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
        hasher.combine(dimensions)
        hasher.combine(metric)
    }

    public static func == (lhs: VectorIndexKind, rhs: VectorIndexKind) -> Bool {
        return lhs.dimensions == rhs.dimensions && lhs.metric == rhs.metric
    }
}
