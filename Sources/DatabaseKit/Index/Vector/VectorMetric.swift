/// Distance function used by a vector index.
public enum VectorMetric: String, Sendable, Hashable {
    case cosine
    case euclidean
    case dotProduct
}
