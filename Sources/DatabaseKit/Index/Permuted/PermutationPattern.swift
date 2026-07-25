/// A declarative permutation that is validated when an index is compiled.
public enum PermutationPattern: Sendable, Equatable, Hashable {
    case identity(size: Int)
    case swapping(_ first: Int, _ second: Int, size: Int)
    case ordering([Int])

    public func resolve() throws(PermutationError) -> Permutation {
        switch self {
        case .identity(let size):
            return try .identity(size: size)
        case .swapping(let first, let second, let size):
            return try .swapping(first, second, size: size)
        case .ordering(let indices):
            return try Permutation(indices: indices)
        }
    }
}
