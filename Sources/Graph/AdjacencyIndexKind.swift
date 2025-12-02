// AdjacencyIndexKind.swift
// GraphIndexModel - Graph adjacency index kind (FDB-independent, iOS-compatible)
//
// Defines metadata for graph adjacency indexes. This file is FDB-independent
// and can be used on all platforms including iOS clients.

import Foundation
import Core

/// Graph adjacency index kind
///
/// Indexes graph edges for efficient traversal queries. Supports both
/// outgoing (source → target) and incoming (target → source) directions.
///
/// **Usage with #Index macro**:
/// ```swift
/// @Persistable
/// struct Edge {
///     var source: String
///     var target: String
///     var label: String
///
///     #Index<Edge>(type: AdjacencyIndexKind(
///         source: \.source,
///         target: \.target,
///         label: \.label,
///         bidirectional: true
///     ))
/// }
/// ```
///
/// **Key structure**:
/// ```
/// // Outgoing edges (source → target)
/// [I]/adj/<label>/<source>/<target> = ''
///
/// // Incoming edges (target → source) - when bidirectional is true
/// [I]/adj_in/<label>/<target>/<source> = ''
/// ```
///
/// **Query patterns**:
/// - Find all outgoing edges from a node: scan [I]/adj/<label>/<source>/
/// - Find all incoming edges to a node: scan [I]/adj_in/<label>/<target>/
/// - Find specific edge: get [I]/adj/<label>/<source>/<target>
public struct AdjacencyIndexKind<Root: Persistable>: IndexKind {
    /// Unique identifier for this index kind
    public static var identifier: String { "adjacency" }

    /// Subspace structure type
    ///
    /// Uses hierarchical structure for organized graph traversal:
    /// - Outgoing: [label]/[source]/[target]
    /// - Incoming: [label]/[target]/[source]
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    /// Source node field name (e.g., "source", "fromNodeID")
    public let sourceField: String

    /// Target node field name (e.g., "target", "toNodeID")
    public let targetField: String

    /// Edge label field name (optional, e.g., "label", "type")
    public let labelField: String?

    /// Whether to create both outgoing and incoming indexes
    ///
    /// When `true`, creates two index entries per edge:
    /// - Outgoing: [adj]/[label]/[source]/[target]
    /// - Incoming: [adj_in]/[label]/[target]/[source]
    ///
    /// This enables efficient bidirectional traversal but doubles write cost.
    public let bidirectional: Bool

    /// All field names for IndexKind protocol
    public var fieldNames: [String] {
        var fields = [sourceField, targetField]
        if let label = labelField {
            fields.append(label)
        }
        return fields
    }

    /// Default index name: "{TypeName}_adjacency_{source}_{target}"
    public var indexName: String {
        let s = sourceField.replacingOccurrences(of: ".", with: "_")
        let t = targetField.replacingOccurrences(of: ".", with: "_")
        if let label = labelField {
            let l = label.replacingOccurrences(of: ".", with: "_")
            return "\(Root.persistableType)_adjacency_\(s)_\(t)_\(l)"
        }
        return "\(Root.persistableType)_adjacency_\(s)_\(t)"
    }

    /// Validate that the indexed fields are appropriate for adjacency index
    ///
    /// - At least source and target fields are required
    /// - All fields must be TupleElement-compatible for key encoding
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }

        // Validate that source and target are Comparable (for consistent ordering)
        for (index, type) in types.prefix(2).enumerated() {
            guard TypeValidation.isComparable(type) else {
                let fieldName = index == 0 ? "source" : "target"
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "\(fieldName) field must be Comparable for adjacency index"
                )
            }
        }
    }

    /// Initialize with KeyPaths
    ///
    /// - Parameters:
    ///   - source: KeyPath to source node ID field
    ///   - target: KeyPath to target node ID field
    ///   - label: KeyPath to edge label field (optional)
    ///   - bidirectional: Whether to create incoming index (default: false)
    public init(
        source: PartialKeyPath<Root>,
        target: PartialKeyPath<Root>,
        label: PartialKeyPath<Root>? = nil,
        bidirectional: Bool = false
    ) {
        self.sourceField = Root.fieldName(for: source)
        self.targetField = Root.fieldName(for: target)
        self.labelField = label.map { Root.fieldName(for: $0) }
        self.bidirectional = bidirectional
    }

    /// Initialize with field names (for Codable reconstruction)
    ///
    /// - Parameters:
    ///   - sourceField: Name of the source node ID field
    ///   - targetField: Name of the target node ID field
    ///   - labelField: Name of the edge label field (optional)
    ///   - bidirectional: Whether to create incoming index (default: false)
    public init(
        sourceField: String,
        targetField: String,
        labelField: String? = nil,
        bidirectional: Bool = false
    ) {
        self.sourceField = sourceField
        self.targetField = targetField
        self.labelField = labelField
        self.bidirectional = bidirectional
    }
}

// MARK: - Codable

extension AdjacencyIndexKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case sourceField
        case targetField
        case labelField
        case bidirectional
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sourceField = try container.decode(String.self, forKey: .sourceField)
        self.targetField = try container.decode(String.self, forKey: .targetField)
        self.labelField = try container.decodeIfPresent(String.self, forKey: .labelField)
        self.bidirectional = try container.decode(Bool.self, forKey: .bidirectional)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceField, forKey: .sourceField)
        try container.encode(targetField, forKey: .targetField)
        try container.encodeIfPresent(labelField, forKey: .labelField)
        try container.encode(bidirectional, forKey: .bidirectional)
    }
}

// MARK: - Hashable

extension AdjacencyIndexKind: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sourceField)
        hasher.combine(targetField)
        hasher.combine(labelField)
        hasher.combine(bidirectional)
    }

    public static func == (lhs: AdjacencyIndexKind, rhs: AdjacencyIndexKind) -> Bool {
        lhs.sourceField == rhs.sourceField &&
        lhs.targetField == rhs.targetField &&
        lhs.labelField == rhs.labelField &&
        lhs.bidirectional == rhs.bidirectional
    }
}
