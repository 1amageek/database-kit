import DatabaseKit
import Testing

@Suite("Permutation")
struct PermutationTests {
    @Test func rejectsEmptyAndNonBijectiveIndices() {
        #expect(throws: PermutationError.empty) {
            _ = try Permutation(indices: [])
        }
        #expect(throws: PermutationError.invalidIndices([0, 0, 2])) {
            _ = try Permutation(indices: [0, 0, 2])
        }
    }

    @Test func factoryFailuresAreTyped() {
        #expect(throws: PermutationError.invalidSize(0)) {
            _ = try Permutation.identity(size: 0)
        }
        #expect(
            throws: PermutationError.positionOutOfBounds(
                position: 3,
                size: 3
            )
        ) {
            _ = try Permutation.swapping(0, 3, size: 3)
        }
    }

    @Test func factoriesConstructValidatedPermutations() throws {
        #expect(try Permutation.identity(size: 3).indices == [0, 1, 2])
        #expect(
            try Permutation.swapping(0, 2, size: 3).indices == [2, 1, 0]
        )
    }

    @Test func appliesAndInvertsCanonicalOrdering() throws {
        let permutation = try Permutation(indices: [1, 2, 0])

        #expect(try permutation.apply(["a", "b", "c"]) == ["b", "c", "a"])
        #expect(
            try permutation.inverse.apply(
                permutation.apply(["a", "b", "c"])
            ) == ["a", "b", "c"]
        )
    }

    @Test func rejectsAnIncompatibleElementCount() throws {
        let permutation = try Permutation(indices: [1, 0])

        #expect(
            throws: PermutationError.elementCountMismatch(
                expected: 2,
                actual: 1
            )
        ) {
            _ = try permutation.apply(["only"])
        }
    }
}
