// RankIndexKind.swift
// RankIndexModel - Rank index metadata (FDB-independent, iOS-compatible)
//
// Defines metadata for ranking and leaderboard indexes. This file is FDB-independent
// and can be used on all platforms including iOS clients.

import Foundation
import Core

/// Rank index kind for leaderboard and ranking queries
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
///     var id: String = ULID().ulidString
///
///     #Index<Player>([\.score], type: RankIndexKind(bucketSize: 10))
///
///     var score: Int64
///     var name: String
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
public struct RankIndexKind<Root: Persistable>: IndexKind {
    /// Identifier: "rank"
    public static var identifier: String { "rank" }

    /// Subspace structure: hierarchical (Range Tree)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field names for this index
    public let fieldNames: [String]

    /// Bucket size for Range Tree
    /// - Controls granularity of count nodes
    /// - Default: 100 (balanced performance)
    /// - Typical range: 10-1000
    public let bucketSize: Int

    /// Default index name: "{TypeName}_rank_{field}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_rank_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPath
    ///
    /// - Parameters:
    ///   - field: KeyPath to the score field
    ///   - bucketSize: Bucket size for Range Tree (default: 100)
    public init(field: PartialKeyPath<Root>, bucketSize: Int = 100) {
        self.fieldNames = [Root.fieldName(for: field)]
        self.bucketSize = bucketSize
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(fieldNames: [String], bucketSize: Int = 100) {
        self.fieldNames = fieldNames
        self.bucketSize = bucketSize
    }

    /// Type validation
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 1 else {
            throw RankIndexError.invalidConfiguration("Rank index requires at least 1 field (score)")
        }
        for type in types {
            guard TypeValidation.isComparable(type) else {
                throw RankIndexError.invalidConfiguration("Rank index requires Comparable types")
            }
        }
    }
}

// MARK: - Hashable Conformance

extension RankIndexKind {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(bucketSize)
    }

    public static func == (lhs: RankIndexKind, rhs: RankIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames && lhs.bucketSize == rhs.bucketSize
    }
}

// MARK: - Rank Index Errors

/// Errors specific to rank index operations
public enum RankIndexError: Error, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case invalidScore(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid rank index configuration: \(message)"
        case .invalidScore(let message):
            return "Invalid score: \(message)"
        }
    }
}
