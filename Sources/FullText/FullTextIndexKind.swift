// FullTextIndexKind.swift
// FullTextIndexModel - Full-text index metadata (FDB-independent, iOS-compatible)
//
// Defines metadata for full-text search indexes. This file is FDB-independent
// and can be used on all platforms including iOS clients.

import Foundation
import Core

/// Tokenization strategy for full-text search
public enum TokenizationStrategy: String, Sendable, Codable, Hashable {
    /// Simple whitespace and punctuation tokenization
    /// - Splits on whitespace and punctuation
    /// - Lowercases all tokens
    /// - Best for: Simple text, Western languages
    case simple

    /// Word-based tokenization with stemming
    /// - Uses word boundaries
    /// - Applies Porter stemmer (English)
    /// - Best for: English text search
    case stem

    /// N-gram tokenization
    /// - Generates character n-grams
    /// - Best for: Fuzzy matching, CJK languages
    case ngram

    /// Keyword tokenization (no splitting)
    /// - Treats entire value as single token
    /// - Best for: Tags, categories, exact phrases
    case keyword
}

/// Full-text index kind for text search
///
/// **Purpose**: Full-text search with inverted index
/// - Term-based search
/// - Phrase search
/// - Multiple tokenization strategies
/// - BM25 or TF-IDF ranking (future)
///
/// **Index Structure**:
/// ```
/// // Inverted index (term → documents)
/// Key: [indexSubspace]["terms"][term][primaryKey]
/// Value: Tuple(position1, position2, ...) or '' (no positions)
///
/// // Document metadata (for ranking)
/// Key: [indexSubspace]["docs"][primaryKey]
/// Value: Tuple(termCount, fieldLength)
/// ```
///
/// **Usage**:
/// ```swift
/// @Persistable
/// struct Article {
///     var id: String = ULID().ulidString
///
///     #Index<Article>(
///         [\.title, \.body],
///         type: FullTextIndexKind(
///             tokenizer: .simple,
///             storePositions: true
///         )
///     )
///
///     var title: String
///     var body: String
/// }
/// ```
public struct FullTextIndexKind<Root: Persistable>: IndexKind {
    /// Identifier: "fulltext"
    public static var identifier: String { "fulltext" }

    /// Subspace structure: hierarchical (inverted index)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field names for this index
    public let fieldNames: [String]

    /// Tokenization strategy
    public let tokenizer: TokenizationStrategy

    /// Whether to store term positions (for phrase queries)
    public let storePositions: Bool

    /// N-gram size (only used when tokenizer is .ngram)
    public let ngramSize: Int

    /// Minimum term length to index
    public let minTermLength: Int

    /// Default index name: "{TypeName}_fulltext_{fields}"
    public var indexName: String {
        let flattenedNames = fieldNames.map { $0.replacingOccurrences(of: ".", with: "_") }
        return "\(Root.persistableType)_fulltext_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - fields: KeyPaths to text fields to index
    ///   - tokenizer: Tokenization strategy (default: .simple)
    ///   - storePositions: Whether to store term positions (default: true)
    ///   - ngramSize: N-gram size for ngram tokenizer (default: 3)
    ///   - minTermLength: Minimum term length to index (default: 2)
    public init(
        fields: [PartialKeyPath<Root>],
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minTermLength: Int = 2
    ) {
        self.fieldNames = fields.map { Root.fieldName(for: $0) }
        self.tokenizer = tokenizer
        self.storePositions = storePositions
        self.ngramSize = ngramSize
        self.minTermLength = minTermLength
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(
        fieldNames: [String],
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minTermLength: Int = 2
    ) {
        self.fieldNames = fieldNames
        self.tokenizer = tokenizer
        self.storePositions = storePositions
        self.ngramSize = ngramSize
        self.minTermLength = minTermLength
    }

    /// Type validation
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard !types.isEmpty else {
            throw FullTextIndexError.invalidConfiguration("Full-text index requires at least 1 field")
        }
    }
}

// MARK: - Hashable Conformance

extension FullTextIndexKind {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Self.identifier)
        hasher.combine(fieldNames)
        hasher.combine(tokenizer)
        hasher.combine(storePositions)
        hasher.combine(ngramSize)
        hasher.combine(minTermLength)
    }

    public static func == (lhs: FullTextIndexKind, rhs: FullTextIndexKind) -> Bool {
        return lhs.fieldNames == rhs.fieldNames &&
            lhs.tokenizer == rhs.tokenizer &&
            lhs.storePositions == rhs.storePositions &&
            lhs.ngramSize == rhs.ngramSize &&
            lhs.minTermLength == rhs.minTermLength
    }
}

// MARK: - Full-Text Index Errors

/// Errors specific to full-text index operations
public enum FullTextIndexError: Error, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case invalidQuery(String)
    case tokenizationFailed(String)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid full-text index configuration: \(message)"
        case .invalidQuery(let message):
            return "Invalid search query: \(message)"
        case .tokenizationFailed(let message):
            return "Tokenization failed: \(message)"
        }
    }
}
