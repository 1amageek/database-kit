// PermutedIndexKind.swift
// Permuted index declaration metadata.

import DatabaseTypes

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
