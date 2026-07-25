import DatabaseTypes
// GraphIndexKind.swift
// Graph - Property graph index metadata


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
///     var label: String
///
///     #Index(
///         .graph(strategy: .adjacency),
///         from: \Follow.follower,
///         edge: \Follow.label,
///         to: \Follow.followee
///     )
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
    public typealias Model = Root

    /// Unique identifier for this index kind
    public static var identifier: String { "graph" }

    /// Subspace structure type
    public static var subspaceStructure: SubspaceStructure { .hierarchical }

    // MARK: - Fields

    public let indexFields: [IndexField<Root>]
    private let includesEdgeField: Bool
    private let includesGraphField: Bool

    public var fromField: String {
        indexFields[0].name
    }

    public var edgeField: String {
        includesEdgeField ? indexFields[1].name : ""
    }

    public var toField: String {
        indexFields[includesEdgeField ? 2 : 1].name
    }

    public var graphField: String? {
        includesGraphField ? indexFields.last?.name : nil
    }

    /// Storage strategy determining number of index orderings
    public let strategy: PropertyGraphIndexStrategy

    /// Physical ordering layout consumed by the execution layer.
    public var storageStrategy: GraphIndexStrategy {
        strategy.storageStrategy
    }

    // MARK: - IndexKind Protocol

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
    public static func validateFields(
        _ fields: [FieldSchema]
    ) throws(IndexValidationError) {
        guard fields.count >= 2 else {
            throw IndexValidationError.invalidFieldCount(
                index: identifier,
                expected: 2,
                actual: fields.count
            )
        }

        for field in fields {
            guard field.type == .string, !field.isArray else {
                throw IndexValidationError.unsupportedField(
                    index: identifier,
                    field: field,
                    reason: "property-graph identity fields must be String or String?"
                )
            }
        }
    }

    // MARK: - Initialization

    public init(
        from: IndexField<Root>,
        edge: IndexField<Root>,
        to: IndexField<Root>,
        graph: IndexField<Root>? = nil,
        strategy: PropertyGraphIndexStrategy = .tripleStore
    ) {
        self.indexFields = [from, edge, to] + (graph.map { [$0] } ?? [])
        self.includesEdgeField = true
        self.includesGraphField = graph != nil
        self.strategy = strategy
    }

    package init(
        canonicalFields: [IndexFieldMetadata],
        includesEdgeField: Bool,
        includesGraphField: Bool,
        strategy: PropertyGraphIndexStrategy = .tripleStore
    ) {
        self.indexFields = canonicalFields.map {
            IndexField<Root>(metadata: $0)
        }
        self.includesEdgeField = includesEdgeField
        self.includesGraphField = includesGraphField
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
        source: IndexField<Root>,
        target: IndexField<Root>,
        label: IndexField<Root>? = nil,
        graph: IndexField<Root>? = nil
    ) -> GraphIndexKind {
        if let label {
            return GraphIndexKind(
                from: source,
                edge: label,
                to: target,
                graph: graph,
                strategy: .adjacency
            )
        }
        return GraphIndexKind(
            canonicalFields: [source.metadata, target.metadata]
                + (graph.map { [$0.metadata] } ?? []),
            includesEdgeField: false,
            includesGraphField: graph != nil,
            strategy: .adjacency
        )
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
        entity: IndexField<Root>,
        relation: IndexField<Root>,
        value: IndexField<Root>,
        graph: IndexField<Root>? = nil
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
        includesEdgeField
    }

    /// Check if graph field is present
    public var hasGraphField: Bool {
        includesGraphField
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
    public var metadata: [String: FieldValue] {
        [
            "strategy": .string(strategy.rawValue),
            "hasEdgeField": .bool(hasEdgeField),
            "hasGraphField": .bool(hasGraphField),
        ]
    }
}
