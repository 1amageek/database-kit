// PermutedIndexKind.swift
// Permuted index declaration metadata.

import Core
import DatabaseValue
import DatabaseTypes

// MARK: - Permutation

/// Represents a permutation of index field ordering
///
/// A permutation defines an alternative ordering for a compound index.
/// For example, given a base index on (A, B, C):
/// - Permutation [0, 1, 2] maintains original order (A, B, C)
/// - Permutation [1, 0, 2] creates ordering (B, A, C)
/// - Permutation [2, 1, 0] creates ordering (C, B, A)
///
/// **Storage Optimization:**
/// Instead of storing duplicate data, permuted indexes only store permuted keys
/// pointing to the primary key. The actual data is stored once in the base index.
///
/// **Example:**
/// ```swift
/// // Base index: compound(["country", "city", "name"])
/// let basePermutation = Permutation.identity(size: 3)  // [0, 1, 2]
///
/// // Permuted index: (city, country, name)
/// let cityFirstPermutation = try Permutation(indices: [1, 0, 2])
/// ```
public struct Permutation: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    /// The permutation indices
    ///
    /// For a base index with N fields, this array must:
    /// - Contain exactly N elements
    /// - Contain all integers from 0 to N-1 exactly once
    public let indices: [Int]

    // MARK: - Initialization

    /// Create a permutation from indices
    /// - Parameter indices: The permutation indices (must be a valid permutation)
    /// - Throws: PermutedIndexError.invalidPermutation if indices are invalid
    public init(indices: [Int]) throws {
        // Validate permutation
        guard !indices.isEmpty else {
            throw PermutedIndexError.invalidPermutation("Permutation cannot be empty")
        }

        let sorted = indices.sorted()
        let expected = Array(0..<indices.count)

        guard sorted == expected else {
            throw PermutedIndexError.invalidPermutation(
                "Permutation must contain all indices 0..<\(indices.count) exactly once. Got: \(indices)"
            )
        }

        self.indices = indices
    }

    private init(validatedIndices: [Int]) {
        self.indices = validatedIndices
    }

    /// Create identity permutation (no reordering)
    /// - Parameter size: Number of fields
    public static func identity(size: Int) -> Permutation {
        precondition(size > 0, "Permutation size must be positive")
        return Permutation(validatedIndices: Array(0..<size))
    }

    /// Create a permutation that swaps two positions in an identity ordering.
    public static func swapping(
        _ first: Int,
        _ second: Int,
        size: Int
    ) -> Permutation {
        precondition(size > 0, "Permutation size must be positive")
        precondition((0..<size).contains(first), "First position is out of bounds")
        precondition((0..<size).contains(second), "Second position is out of bounds")
        var indices = Array(0..<size)
        indices.swapAt(first, second)
        return Permutation(validatedIndices: indices)
    }

    // MARK: - Operations

    /// Apply this permutation to a list of elements
    /// - Parameter elements: The elements to permute
    /// - Returns: Permuted elements
    /// - Throws: PermutedIndexError.invalidPermutation if element count doesn't match
    public func apply<T>(_ elements: [T]) throws -> [T] {
        guard elements.count == indices.count else {
            throw PermutedIndexError.invalidPermutation(
                "Cannot apply permutation of size \(indices.count) to \(elements.count) elements"
            )
        }

        return indices.map { elements[$0] }
    }

    /// Inverse of this permutation
    ///
    /// If P is a permutation, then P.inverse.apply(P.apply(x)) == x
    public var inverse: Permutation {
        var inverseIndices = [Int](repeating: 0, count: indices.count)
        for (newPos, oldPos) in indices.enumerated() {
            inverseIndices[oldPos] = newPos
        }
        return Permutation(validatedIndices: inverseIndices)
    }

    /// Check if this is the identity permutation
    public var isIdentity: Bool {
        return indices == Array(0..<indices.count)
    }

    /// Size of the permutation (number of fields)
    public var size: Int {
        return indices.count
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        return "[\(indices.map(String.init).joined(separator: ", "))]"
    }
}

// MARK: - PermutedIndexKind

/// Permuted index kind for alternative field orderings
///
/// **Purpose**: Efficiently support multiple query patterns on compound indexes
/// - Reorder fields without duplicating data storage
/// - Enable different prefix queries on the same set of fields
/// - Reduce storage overhead compared to maintaining separate indexes
///
/// **Storage Savings:**
/// If you need to query on multiple orderings of (A, B, C):
/// - Without permutation: 3 full indexes = 300% storage
/// - With permutation: 1 base + 2 permuted = ~140% storage (60% savings)
///
/// **Index Structure**:
/// ```
/// // Permuted index entries (reordered fields + primary key)
/// Key: [indexSubspace][permuted_field_0][permuted_field_1]...[permuted_field_n][primaryKey]
/// Value: '' (empty - data is stored in base entity)
/// ```
///
/// **Usage**:
/// ```swift
/// // Base compound index on (country, city, name)
/// #Index(ScalarIndexKind<Location>(fields: [\.country, \.city, \.name]))
///
/// // Permuted index for (city, country, name) ordering
/// #Index(
///     PermutedIndexKind<Location>(
///         fields: [\.country, \.city, \.name],
///         permutation: .swapping(0, 1, size: 3)
///     )
/// )
/// ```
///
/// **Query Examples**:
/// - Base index (country, city, name): Best for queries starting with country
/// - Permuted index (city, country, name): Best for queries starting with city
public struct PermutedIndexKind<Root: Persistable>: IndexKind {
    /// Identifier: "permuted"
    public static var identifier: String { "permuted" }

    /// Subspace structure: flat (simple key-value pairs)
    public static var subspaceStructure: SubspaceStructure { .flat }

    /// Field names for this index
    public let fieldNames: [String]

    /// The permutation defining field reordering
    public let permutation: Permutation

    /// Default index name: "{TypeName}_permuted_{fields}_{permutation}"
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        let permStr = permutation.indices.map(String.init).joined(separator: "")
        return "\(Root.persistableType)_permuted_\(flattenedNames.joined(separator: "_"))_\(permStr)"
    }

    /// Initialize with KeyPaths and permutation
    ///
    /// - Parameters:
    ///   - fields: KeyPaths to fields in original order
    ///   - permutation: The permutation to apply to field ordering
    public init(fields: [PartialKeyPath<Root>], permutation: Permutation) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
        self.permutation = permutation
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String], permutation: Permutation) {
        self.fieldNames = fieldNames
        self.permutation = permutation
    }

    public func validateConfiguration() throws(IndexTypeValidationError) {
        guard permutation.size == fieldNames.count else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Permutation size must match the indexed field count"
            )
        }
    }

    /// Type validation
    ///
    /// Permuted indexes require at least 2 fields (single field doesn't need reordering)
    public static func validateTypes(
        _ types: [Any.Type]
    ) throws(IndexTypeValidationError) {
        guard types.count >= 2 else {
            throw .invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }
        // All fields must be Comparable for index ordering
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw .unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "Permuted index requires Comparable types"
                )
            }
        }
    }
}

// MARK: - Hashable Conformance

extension PermutedIndexKind {
    public var metadata: [String: FieldValue] {
        [
            "permutation": .array(
                permutation.indices.map { .int64(Int64($0)) }
            )
        ]
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(permutation)
    }

    public static func == (lhs: PermutedIndexKind, rhs: PermutedIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames && lhs.permutation == rhs.permutation
    }
}

// MARK: - Permuted Index Errors

/// Errors specific to permuted index operations
public enum PermutedIndexError: Error, CustomStringConvertible, Sendable {
    case invalidPermutation(String)
    case invalidConfiguration(String)
    case fieldCountMismatch(expected: Int, got: Int)
    case corruptedEntry(expectedMinimumElementCount: Int, actual: Int)

    public var description: String {
        switch self {
        case .invalidPermutation(let message):
            return "Invalid permutation: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid permuted index configuration: \(message)"
        case .fieldCountMismatch(let expected, let got):
            return "Field count mismatch: permutation expects \(expected) fields, got \(got)"
        case .corruptedEntry(let expected, let actual):
            return "Corrupted permuted index entry: expected at least \(expected) elements, got \(actual)"
        }
    }
}
