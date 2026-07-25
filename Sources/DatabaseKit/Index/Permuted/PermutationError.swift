/// A failure to construct or apply a finite permutation.
public enum PermutationError:
    Error,
    Sendable,
    Equatable,
    CustomStringConvertible {
    case empty
    case invalidIndices([Int])
    case invalidSize(Int)
    case positionOutOfBounds(position: Int, size: Int)
    case elementCountMismatch(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .empty:
            return "A permutation must contain at least one index"
        case .invalidIndices(let indices):
            return "A permutation must contain every index in 0..<\(indices.count) exactly once: \(indices)"
        case .invalidSize(let size):
            return "A permutation size must be positive, got \(size)"
        case .positionOutOfBounds(let position, let size):
            return "Permutation position \(position) is outside 0..<\(size)"
        case .elementCountMismatch(let expected, let actual):
            return "A permutation of \(expected) positions cannot be applied to \(actual) elements"
        }
    }
}
