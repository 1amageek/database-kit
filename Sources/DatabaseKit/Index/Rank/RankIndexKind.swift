// RankIndexKind.swift
// Rank index declaration metadata.

import DatabaseTypes

/// Rank index kind for leaderboard and ranking queries
///
/// **Type-Safe Design**: The `Score` type parameter preserves the score type,
/// ensuring rankings work correctly with the original numeric type.
///
/// **Purpose**: Efficiently answer ranking queries
/// - Leaderboards (top-K queries)
/// - Percentile calculations (95th percentile)
/// - Rank lookup (what's my rank?)
/// - Count queries (how many above/below score?)
///
/// **Algorithm**: Range Tree (hierarchical bucket structure)
/// - O(log n) count queries
/// - O(log n + k) top-K queries
/// - Atomic score updates
///
/// **Index Structure**:
/// ```
/// // Leaf level (individual scores)
/// Key: [indexSubspace]["scores"][score][primaryKey]
/// Value: '' (empty)
///
/// // Count nodes (hierarchical buckets)
/// Key: [indexSubspace]["count"][level][bucketBoundary]
/// Value: Int64 (count in bucket)
/// ```
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Player {
///     var id: String
///     var score: Int64
///     var name: String
///
///     #Index(RankIndexKind<Player, Int64>(field: \.score, bucketSize: 10))
/// }
///
/// // Queries:
/// // - Top 10 players: scan scores descending, limit 10
/// // - Player rank: count all scores > player.score
/// // - 95th percentile: count * 0.95, then find score at that rank
/// ```
///
/// **Bucket Size**: Controls tree height and performance
/// - Small (10): More levels, slower writes, faster counts
/// - Medium (100): Balanced (default)
/// - Large (1000): Fewer levels, faster writes, slower counts
public struct RankIndexKind<Root: Persistable, Score: IndexNumericValue>: IndexKind {
    /// Identifier: "rank"
    public static var identifier: String { "rank" }

    /// Subspace structure: hierarchical (Range Tree)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field names for this index
    public let fieldNames: [String]

    /// Stable score scalar type used by the runtime.
    public let scoreType: IndexScalarType

    /// Bucket size for Range Tree
    /// - Controls granularity of count nodes
    /// - Default: 100 (balanced performance)
    /// - Typical range: 10-1000
    public let bucketSize: Int

    /// Default index name: "{TypeName}_rank_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        return "\(Root.persistableType)_rank_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath - type is inferred from KeyPath
    ///
    /// - Parameters:
    ///   - field: KeyPath to the score field (type inferred)
    ///   - bucketSize: Bucket size for Range Tree (default: 100)
    public init(field: KeyPath<Root, Score>, bucketSize: Int = 100) {
        self.fieldNames = [Root.fieldName(for: field)]
        self.scoreType = Score.indexScalarType
        self.bucketSize = bucketSize
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        fieldNames: [String],
        scoreType: IndexScalarType,
        bucketSize: Int = 100
    ) {
        self.fieldNames = fieldNames
        self.scoreType = scoreType
        self.bucketSize = bucketSize
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard bucketSize > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Bucket size must be positive"
            )
        }
    }

    /// Persisted field validation
    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count == 1 else {
            throw .invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        for field in fields {
            guard field.isNumeric else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Rank score fields must be numeric"
                )
            }
        }
    }
}

// MARK: - Hashable Conformance

extension RankIndexKind {
    public var metadata: [String: FieldValue] {
        [
            "scoreType": .string(scoreType.rawValue),
            "bucketSize": .int64(Int64(bucketSize)),
        ]
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(scoreType)
        hasher.combine(bucketSize)
    }

    public static func == (lhs: RankIndexKind, rhs: RankIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames
            && lhs.scoreType == rhs.scoreType
            && lhs.bucketSize == rhs.bucketSize
    }
}
