// FullTextIndexKind.swift
// Full-text index declaration metadata.

import DatabaseTypes

/// Tokenization strategy for full-text search
public enum TokenizationStrategy: String, Sendable, Hashable {
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
///     var id: String
///
///     #Index(
///         FullTextIndexKind<Article>(
///             fields: [\.title, \.body],
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
    public typealias Model = Root

    /// Identifier: "fulltext"
    public static var identifier: String { "fulltext" }

    /// Subspace structure: hierarchical (inverted index)
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Field names for this index
    public let indexFields: [IndexField<Root>]

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
        let flattenedNames = fieldNames.map {
            UTF8Text.replacingOccurrences(in: $0, of: ".", with: "_")
        }
        return "\(Root.persistableType)_fulltext_\(flattenedNames.joined(separator: "_"))"
    }

    /// Initialize with model-scoped fields.
    ///
    /// - Parameters:
    ///   - fields: Text fields to index
    ///   - tokenizer: Tokenization strategy (default: .simple)
    ///   - storePositions: Whether to store term positions (default: true)
    ///   - ngramSize: N-gram size for ngram tokenizer (default: 3)
    ///   - minTermLength: Minimum term length to index (default: 2)
    public init(
        fields: [IndexField<Root>],
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minTermLength: Int = 2
    ) {
        self.indexFields = fields
        self.tokenizer = tokenizer
        self.storePositions = storePositions
        self.ngramSize = ngramSize
        self.minTermLength = minTermLength
    }

    /// Initialize with field name strings (from canonical metadata)
    public init(
        canonicalFields: [IndexFieldMetadata],
        tokenizer: TokenizationStrategy = .simple,
        storePositions: Bool = true,
        ngramSize: Int = 3,
        minTermLength: Int = 2
    ) {
        self.indexFields = canonicalFields.map {
            IndexField<Root>(metadata: $0)
        }
        self.tokenizer = tokenizer
        self.storePositions = storePositions
        self.ngramSize = ngramSize
        self.minTermLength = minTermLength
    }

    public func validateConfiguration() throws(IndexValidationError) {
        guard ngramSize > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "N-gram size must be positive"
            )
        }
        guard minTermLength > 0 else {
            throw .invalidConfiguration(
                index: Self.identifier,
                reason: "Minimum term length must be positive"
            )
        }
    }

    /// Persisted field validation
    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard !fields.isEmpty else {
            throw .invalidFieldCount(
                index: identifier,
                expected: 1,
                actual: fields.count
            )
        }
        for field in fields {
            guard field.type == .string, !field.isArray else {
                throw .unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "Full-text index fields must be String"
                )
            }
        }
    }
}

// MARK: - Hashable Conformance

extension FullTextIndexKind {
    public var metadata: [String: FieldValue] {
        [
            "tokenizer": .string(tokenizer.rawValue),
            "storePositions": .bool(storePositions),
            "ngramSize": .int64(Int64(ngramSize)),
            "minTermLength": .int64(Int64(minTermLength)),
        ]
    }

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
