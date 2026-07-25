/// A validated ordering of a finite set of positions.
public struct Permutation:
    Sendable,
    Equatable,
    Hashable,
    CustomStringConvertible {
    /// Every integer in `0..<count`, in the order produced by the permutation.
    public let indices: [Int]

    public init(
        indices: [Int]
    ) throws(PermutationError) {
        guard !indices.isEmpty else {
            throw .empty
        }
        guard indices.sorted() == Array(indices.indices) else {
            throw .invalidIndices(indices)
        }
        self.indices = indices
    }

    private init(validatedIndices: [Int]) {
        self.indices = validatedIndices
    }

    /// Returns an ordering that leaves every position unchanged.
    ///
    public static func identity(
        size: Int
    ) throws(PermutationError) -> Permutation {
        guard size > 0 else {
            throw .invalidSize(size)
        }
        return Permutation(validatedIndices: Array(0..<size))
    }

    /// Returns an identity ordering with two positions exchanged.
    ///
    public static func swapping(
        _ first: Int,
        _ second: Int,
        size: Int
    ) throws(PermutationError) -> Permutation {
        guard size > 0 else {
            throw .invalidSize(size)
        }
        guard (0..<size).contains(first) else {
            throw .positionOutOfBounds(position: first, size: size)
        }
        guard (0..<size).contains(second) else {
            throw .positionOutOfBounds(position: second, size: size)
        }
        var indices = Array(0..<size)
        indices.swapAt(first, second)
        return Permutation(validatedIndices: indices)
    }

    /// Returns `elements` in the order defined by this permutation.
    public func apply<Element>(
        _ elements: [Element]
    ) throws(PermutationError) -> [Element] {
        guard elements.count == indices.count else {
            throw .elementCountMismatch(
                expected: indices.count,
                actual: elements.count
            )
        }
        return indices.map { elements[$0] }
    }

    public var inverse: Permutation {
        var inverseIndices = [Int](repeating: 0, count: indices.count)
        for (newPosition, oldPosition) in indices.enumerated() {
            inverseIndices[oldPosition] = newPosition
        }
        return Permutation(validatedIndices: inverseIndices)
    }

    public var isIdentity: Bool {
        indices == Array(indices.indices)
    }

    public var size: Int {
        indices.count
    }

    public var description: String {
        "[\(indices.map(String.init).joined(separator: ", "))]"
    }
}
