import DatabaseTypes
// GraphIndexKind.swift
// Graph - Property graph index metadata

import Core
import DatabaseValue

/// Declarative metadata for a property graph edge index.
///
/// Entities remain the source of truth. The execution layer maintains the
/// selected derived orderings in the same transaction as entity mutations.
/// Every property-graph identity field is a `String`. RDF datasets use
/// `RDFQuadIndexKind` because RDF term roles and default-graph semantics are
/// different from property graph strings.
///
/// **Usage with #Index macro**:
/// ```swift
/// // Social graph (follows)
/// @Persistable
/// struct Follow {
///     var follower: String
///     var followee: String
///
///     #Index<Follow>(type: GraphIndexKind.adjacency(
///         source: \.follower,
///         target: \.followee
///     ))
/// }
/// ```
///
/// **Key structure** (depends on strategy):
/// ```
/// adjacency (2-index):
///   [out]/[from]/[edge]/[to]
///   [in]/[to]/[edge]/[from]
///
/// tripleStore (3-index):
///   [spo]/[from]/[edge]/[to]
///   [pos]/[edge]/[to]/[from]
///   [osp]/[to]/[from]/[edge]
///
/// hexastore (6-index):
///   All 6 permutations of (from, edge, to)
/// ```
public struct GraphIndexKind<Root: Persistable>: IndexKind {
    /// Unique identifier for this index kind
    public static var identifier: String { "graph" }

    /// Subspace structure type
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    // MARK: - Fields

    /// Source node field name.
    public let fromField: String

    /// Edge label field name.
    /// Empty string means no edge field (single edge type)
    public let edgeField: String

    /// Target node field name.
    public let toField: String

    /// Optional property-graph namespace field name.
    public let graphField: String?

    /// Storage strategy determining number of index orderings
    public let strategy: PropertyGraphIndexStrategy

    /// Physical ordering layout consumed by the execution layer.
    public var storageStrategy: GraphIndexStrategy {
        strategy.storageStrategy
    }

    // MARK: - IndexKind Protocol

    /// All field names for IndexKind protocol
    public var fieldNames: [String] {
        var fields: [String]
        if edgeField.isEmpty {
            fields = [fromField, toField]
        } else {
            fields = [fromField, edgeField, toField]
        }
        if let graphField {
            fields.append(graphField)
        }
        return fields
    }

    /// Default index name
    public var indexName: String {
        let f = UTF8Text.replacingOccurrences(
            in: fromField,
            of: ".",
            with: "_"
        )
        let t = UTF8Text.replacingOccurrences(
            in: toField,
            of: ".",
            with: "_"
        )
        var name: String
        if edgeField.isEmpty {
            name = "\(Root.persistableType)_graph_\(f)_\(t)"
        } else {
            let e = UTF8Text.replacingOccurrences(
                in: edgeField,
                of: ".",
                with: "_"
            )
            name = "\(Root.persistableType)_graph_\(f)_\(e)_\(t)"
        }
        if let graphField {
            let g = UTF8Text.replacingOccurrences(
                in: graphField,
                of: ".",
                with: "_"
            )
            name += "_\(g)"
        }
        return name
    }

    /// Validate that every property-graph identity field is a String.
    public static func validateTypes(_ types: [Any.Type]) throws {
        guard types.count >= 2 else {
            throw IndexTypeValidationError.invalidTypeCount(
                index: identifier,
                expected: 2,
                actual: types.count
            )
        }

        for type in types {
            guard isPropertyGraphString(type) else {
                throw IndexTypeValidationError.unsupportedType(
                    index: identifier,
                    type: type,
                    reason: "property-graph identity fields must be String or String?"
                )
            }
        }
    }

    private static func isPropertyGraphString(_ type: Any.Type) -> Bool {
        if type == String.self { return true }
        guard let optionalType = type as? any GraphOptionalType.Type else {
            return false
        }
        return optionalType.wrappedType == String.self
    }

    // MARK: - Initialization

    /// Initialize with all parameters
    ///
    /// - Parameters:
    ///   - from: KeyPath to from/source/subject field
    ///   - edge: KeyPath to edge/label/predicate field
    ///   - to: KeyPath to to/target/object field
    ///   - graph: Optional KeyPath to graph/named graph field
    ///   - strategy: Storage strategy (default: .tripleStore)
    public init(
        from: PartialKeyPath<Root>,
        edge: PartialKeyPath<Root>,
        to: PartialKeyPath<Root>,
        graph: PartialKeyPath<Root>? = nil,
        strategy: PropertyGraphIndexStrategy = .tripleStore
    ) {
        self.fromField = Root.fieldName(for: from)
        self.edgeField = Root.fieldName(for: edge)
        self.toField = Root.fieldName(for: to)
        self.graphField = graph.map { Root.fieldName(for: $0) }
        self.strategy = strategy
    }

    /// Initialize with field name strings (for Codable reconstruction)
    public init(
        fromField: String,
        edgeField: String,
        toField: String,
        graphField: String? = nil,
        strategy: PropertyGraphIndexStrategy = .tripleStore
    ) {
        self.fromField = fromField
        self.edgeField = edgeField
        self.toField = toField
        self.graphField = graphField
        self.strategy = strategy
    }

    // MARK: - Convenience Initializers

    /// Create adjacency index for simple graph edges
    ///
    /// Uses graph terminology (source/target) with optional label.
    /// Default strategy is `.adjacency` (2-index out/in).
    ///
    /// - Parameters:
    ///   - source: KeyPath to source node field
    ///   - target: KeyPath to target node field
    ///   - label: Optional KeyPath to edge label field
    ///   - graph: Optional KeyPath to named graph field
    /// - Returns: GraphIndexKind configured for adjacency queries
    public static func adjacency(
        source: PartialKeyPath<Root>,
        target: PartialKeyPath<Root>,
        label: PartialKeyPath<Root>? = nil,
        graph: PartialKeyPath<Root>? = nil
    ) -> GraphIndexKind {
        if let label = label {
            return GraphIndexKind(
                from: source,
                edge: label,
                to: target,
                graph: graph,
                strategy: .adjacency
            )
        } else {
            return GraphIndexKind(
                fromField: Root.fieldName(for: source),
                edgeField: "",
                toField: Root.fieldName(for: target),
                graphField: graph.map { Root.fieldName(for: $0) },
                strategy: .adjacency
            )
        }
    }

    /// Create high-performance knowledge graph index
    ///
    /// Uses hexastore strategy (6-index) for maximum query performance.
    /// Best for read-heavy workloads with diverse query patterns.
    ///
    /// - Parameters:
    ///   - entity: KeyPath to entity/subject field
    ///   - relation: KeyPath to relation/predicate field
    ///   - value: KeyPath to value/object field
    ///   - graph: Optional KeyPath to named graph field
    /// - Returns: GraphIndexKind with hexastore strategy
    public static func knowledgeGraph(
        entity: PartialKeyPath<Root>,
        relation: PartialKeyPath<Root>,
        value: PartialKeyPath<Root>,
        graph: PartialKeyPath<Root>? = nil
    ) -> GraphIndexKind {
        GraphIndexKind(
            from: entity,
            edge: relation,
            to: value,
            graph: graph,
            strategy: .hexastore
        )
    }

    // MARK: - Query Support

    /// Check if edge field is present
    public var hasEdgeField: Bool {
        !edgeField.isEmpty
    }

    /// Check if graph field is present
    public var hasGraphField: Bool {
        graphField != nil
    }
}

private protocol GraphOptionalType {
    static var wrappedType: Any.Type { get }
}

extension Optional: GraphOptionalType {
    fileprivate static var wrappedType: Any.Type { Wrapped.self }
}

// MARK: - Codable

extension GraphIndexKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case fromField
        case edgeField
        case toField
        case graphField
        case strategy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fromField = try container.decode(String.self, forKey: .fromField)
        self.edgeField = try container.decode(String.self, forKey: .edgeField)
        self.toField = try container.decode(String.self, forKey: .toField)
        self.graphField = try container.decodeIfPresent(String.self, forKey: .graphField)
        self.strategy = try container.decode(
            PropertyGraphIndexStrategy.self,
            forKey: .strategy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fromField, forKey: .fromField)
        try container.encode(edgeField, forKey: .edgeField)
        try container.encode(toField, forKey: .toField)
        try container.encodeIfPresent(graphField, forKey: .graphField)
        try container.encode(strategy, forKey: .strategy)
    }
}

// MARK: - Hashable

extension GraphIndexKind: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fromField)
        hasher.combine(edgeField)
        hasher.combine(toField)
        hasher.combine(graphField)
        hasher.combine(strategy)
    }

    public static func == (lhs: GraphIndexKind, rhs: GraphIndexKind) -> Bool {
        lhs.fromField == rhs.fromField &&
        lhs.edgeField == rhs.edgeField &&
        lhs.toField == rhs.toField &&
        lhs.graphField == rhs.graphField &&
        lhs.strategy == rhs.strategy
    }
}

extension GraphIndexKind {
    public var metadata: [String: IndexMetadataValue] {
        [
            "strategy": .string(strategy.rawValue),
            "hasEdgeField": .bool(hasEdgeField),
            "hasGraphField": .bool(hasGraphField),
        ]
    }
}
