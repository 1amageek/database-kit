/// DataSource.swift
/// Unified data source representation for SQL and SPARQL
///
/// Reference:
/// - ISO/IEC 9075:2023 (FROM clause)
/// - ISO/IEC 9075-16:2023 (SQL/PGQ GRAPH_TABLE)
/// - W3C SPARQL 1.1/1.2 (Graph Patterns, SERVICE)

import DatabaseTypes
import DatabaseValue

/// Table reference (SQL)
public struct TableRef: Sendable, Equatable, Hashable {
    /// Schema name (optional)
    public let schema: String?

    /// Table name
    public let table: String

    /// Alias (optional)
    public let alias: String?

    /// Typed values for the table's compiled dynamic directory components.
    public let partitions: FieldObject

    public init(
        schema: String? = nil,
        table: String,
        alias: String? = nil,
        partitions: FieldObject = FieldObject()
    ) {
        self.schema = schema
        self.table = table
        self.alias = alias
        self.partitions = partitions
    }

    /// Create a simple table reference
    public init(
        _ table: String,
        partitions: FieldObject = FieldObject()
    ) {
        self.schema = nil
        self.table = table
        self.alias = nil
        self.partitions = partitions
    }

    /// Returns the effective name (alias if present, otherwise table name)
    public var effectiveName: String {
        alias ?? table
    }
}

extension TableRef: CustomStringConvertible {
    public var description: String {
        var result = ""
        if let schema = schema {
            result += "\(SQLEscape.identifier(schema))."
        }
        result += SQLEscape.identifier(table)
        if let alias = alias {
            result += " AS \(SQLEscape.identifier(alias))"
        }
        return result
    }
}

extension TableRef {
    /// Generate unquoted table reference (for display purposes only)
    /// WARNING: Do not use this for SQL generation - use description instead
    public var displayName: String {
        var result = ""
        if let schema = schema {
            result += "\(schema)."
        }
        result += table
        if let alias = alias {
            result += " AS \(alias)"
        }
        return result
    }
}

/// JOIN type
public enum JoinType: String, Sendable, Equatable, Hashable {
    case inner
    case left
    case right
    case full
    case cross
    case natural
    case naturalLeft
    case naturalRight
    case naturalFull

    /// LATERAL JOIN (correlated subquery)
    case lateral
    case leftLateral
}

/// JOIN clause
public struct JoinClause: Sendable, Equatable, Hashable {
    public let type: JoinType
    public let left: DataSource
    public let right: DataSource
    public let condition: JoinCondition?

    public init(type: JoinType, left: DataSource, right: DataSource, condition: JoinCondition? = nil) {
        self.type = type
        self.left = left
        self.right = right
        self.condition = condition
    }
}

/// JOIN condition
public enum JoinCondition: Sendable, Equatable, Hashable {
    /// ON condition: ON expr
    case on(Expression)

    /// USING columns: USING (col1, col2)
    case using([String])
}

/// Named subquery (WITH clause / CTE)
public struct NamedSubquery: Sendable, Equatable, Hashable {
    public let name: String
    public let columns: [String]?
    public let query: SelectQuery
    public let materialized: Materialization?

    public init(
        name: String,
        columns: [String]? = nil,
        query: SelectQuery,
        materialized: Materialization? = nil
    ) {
        self.name = name
        self.columns = columns
        self.query = query
        self.materialized = materialized
    }
}

/// CTE materialization hint
public enum Materialization: String, Sendable, Equatable, Hashable {
    case materialized
    case notMaterialized
}

/// Projection item (SELECT clause item)
public struct ProjectionItem: Sendable, Equatable, Hashable {
    public let expression: Expression
    public let alias: String?

    public init(_ expression: Expression, alias: String? = nil) {
        self.expression = expression
        self.alias = alias
    }

    /// Create a simple column projection
    public static func column(_ name: String) -> ProjectionItem {
        ProjectionItem(.column(ColumnRef(column: name)))
    }

    /// Create an aliased projection
    public static func column(_ name: String, as alias: String) -> ProjectionItem {
        ProjectionItem(.column(ColumnRef(column: name)), alias: alias)
    }
}

/// Projection (SELECT clause)
public enum Projection: Sendable, Equatable, Hashable {
    /// SELECT *
    case all

    /// SELECT table.*
    case allFrom(String)

    /// SELECT expr1, expr2, ...
    case items([ProjectionItem])

    /// SELECT DISTINCT expr1, expr2, ...
    case distinctItems([ProjectionItem])
}

/// Generic logical source reference.
///
/// Allows `QueryIR` to address extensible logical sources without enumerating
/// feature-specific cases in `DataSource`.
public struct LogicalSourceRef: Sendable, Equatable, Hashable {
    public let kindIdentifier: String
    public let identifier: String
    public let alias: String?

    public init(
        kindIdentifier: String,
        identifier: String,
        alias: String? = nil
    ) {
        self.kindIdentifier = kindIdentifier
        self.identifier = identifier
        self.alias = alias
    }

    public var effectiveName: String {
        alias ?? identifier
    }
}

public enum LogicalSourceKind {
    public static let polymorphic = "polymorphic"
}

/// Unified data source representation.
///
/// `DataSource` intentionally models the stable core query languages:
/// relational sources, SQL/PGQ graph tables, and SPARQL graph patterns.
/// Optional index families and future feature-specific reads must use
/// `SelectQuery.accessPath` or `DataSource.logical(LogicalSourceRef)` so adding
/// a new index family does not require adding another enum case here.
public indirect enum DataSource: Sendable, Equatable, Hashable {
    // MARK: - Relational Sources

    /// Single table reference
    case table(TableRef)

    /// Extensible logical source
    case logical(LogicalSourceRef)

    /// Subquery as data source
    case subquery(SelectQuery, alias: String)

    /// JOIN operation
    case join(JoinClause)

    /// Values clause (inline data)
    case values([[Literal]], columnNames: [String]?)

    // MARK: - Core Graph Sources (SQL/PGQ)

    /// GRAPH_TABLE (graph_name, MATCH pattern)
    case graphTable(GraphTableSource)

    // MARK: - Core SPARQL Sources

    /// Basic graph pattern (triple patterns)
    case graphPattern(GraphPattern)

    /// Named graph: GRAPH <name> { pattern }
    case namedGraph(name: String, pattern: GraphPattern)

    /// SERVICE clause (federation)
    case service(endpoint: String, pattern: GraphPattern, silent: Bool)

    // MARK: - Set Operations

    /// UNION of multiple sources
    case union([DataSource])

    /// UNION ALL (SQL)
    case unionAll([DataSource])

    /// INTERSECT
    case intersect([DataSource])

    /// EXCEPT / MINUS
    case except(DataSource, DataSource)
}

// MARK: - Graph Table

/// A SQL/PGQ graph table source.
public struct GraphTableSource: Sendable, Equatable, Hashable {
    public let graphName: String
    public let matchPattern: MatchPattern
    public let columns: [GraphTableColumn]?
    public let alias: String?

    public init(
        graphName: String,
        matchPattern: MatchPattern,
        columns: [GraphTableColumn]? = nil,
        alias: String? = nil
    ) {
        self.graphName = graphName
        self.matchPattern = matchPattern
        self.columns = columns
        self.alias = alias
    }
}

/// Column definition for GRAPH_TABLE
public struct GraphTableColumn: Sendable, Equatable, Hashable {
    public let expression: Expression
    public let alias: String

    public init(expression: Expression, alias: String) {
        self.expression = expression
        self.alias = alias
    }
}

/// A SQL/PGQ graph match pattern.
public struct MatchPattern: Sendable, Equatable, Hashable {
    public let paths: [PathPattern]
    public let `where`: Expression?

    public init(paths: [PathPattern], where: Expression? = nil) {
        self.paths = paths
        self.`where` = `where`
    }
}

/// A named or anonymous graph path pattern.
public struct PathPattern: Sendable, Equatable, Hashable {
    public let pathVariable: String?
    public let elements: [PathElement]
    public let mode: PathMode?

    public init(pathVariable: String? = nil, elements: [PathElement], mode: PathMode? = nil) {
        self.pathVariable = pathVariable
        self.elements = elements
        self.mode = mode
    }
}

/// Path element (node or edge)
public enum PathElement: Sendable, Equatable, Hashable {
    case node(NodePattern)
    case edge(EdgePattern)
    case quantified(PathPattern, quantifier: PathQuantifier)
    case alternation([PathPattern])
}

/// Property binding for graph patterns (key-value pair)
public struct PropertyBinding: Sendable, Equatable, Hashable {
    public let key: String
    public let value: Expression

    public init(key: String, value: Expression) {
        self.key = key
        self.value = value
    }
}

/// Node pattern
public struct NodePattern: Sendable, Equatable, Hashable {
    public let variable: String?
    public let labels: [String]?
    public let properties: [PropertyBinding]?

    public init(variable: String? = nil, labels: [String]? = nil, properties: [PropertyBinding]? = nil) {
        self.variable = variable
        self.labels = labels
        self.properties = properties
    }
}

/// Edge pattern
public struct EdgePattern: Sendable, Equatable, Hashable {
    public let variable: String?
    public let labels: [String]?
    public let properties: [PropertyBinding]?
    public let direction: EdgeDirection

    public init(
        variable: String? = nil,
        labels: [String]? = nil,
        properties: [PropertyBinding]? = nil,
        direction: EdgeDirection
    ) {
        self.variable = variable
        self.labels = labels
        self.properties = properties
        self.direction = direction
    }
}

/// Edge direction
public enum EdgeDirection: String, Sendable, Equatable, Hashable {
    /// Outgoing edge: ->
    case outgoing

    /// Incoming edge: <-
    case incoming

    /// Undirected edge: -
    case undirected

    /// Any direction: <->
    case any
}

/// Path quantifier
public enum PathQuantifier: Sendable, Equatable, Hashable {
    /// Exactly n repetitions: {n}
    case exactly(Int)

    /// Range: {min, max}, {min,}, {,max}
    case range(min: Int?, max: Int?)

    /// Zero or more: *
    case zeroOrMore

    /// One or more: +
    case oneOrMore

    /// Zero or one: ?
    case zeroOrOne
}

/// Path mode (traversal strategy)
public enum PathMode: Sendable, Equatable, Hashable {
    /// Default - allows repeated nodes/edges
    case walk

    /// No repeated edges
    case trail

    /// No repeated nodes (acyclic)
    case acyclic

    /// No repeated nodes or edges
    case simple

    /// Any shortest path
    case anyShortest

    /// All shortest paths
    case allShortest

    /// K shortest paths
    case shortestK(Int)
}

/// Placeholder for GraphPattern (defined in SPARQL/GraphPattern.swift)
public indirect enum GraphPattern: Sendable, Equatable, Hashable {
    case basic(BasicGraphPattern)
    case join(GraphPattern, GraphPattern)
    case optional(GraphPattern, GraphPattern)
    case union(GraphPattern, GraphPattern)
    case filter(GraphPattern, Expression)
    case minus(GraphPattern, GraphPattern)
    case graph(name: SPARQLTerm, pattern: GraphPattern)
    case service(endpoint: String, pattern: GraphPattern, silent: Bool)
    case bind(GraphPattern, variable: String, expression: Expression)
    case values(variables: [String], bindings: [[Literal?]])
    case subquery(SelectQuery)
    case groupBy(GraphPattern, expressions: [Expression], aggregates: [AggregateBinding])
    case lateral(GraphPattern, GraphPattern)
}

/// Placeholder for TriplePattern (defined in SPARQL/TriplePattern.swift)
public struct TriplePattern: Sendable, Equatable, Hashable {
    public let subject: SPARQLTerm
    public let predicate: SPARQLTerm
    public let object: SPARQLTerm

    public init(subject: SPARQLTerm, predicate: SPARQLTerm, object: SPARQLTerm) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }
}

/// SPARQL term types (RDF terms)
/// Reference: W3C SPARQL 1.1/1.2, RDF 1.1, RDF-star
public indirect enum SPARQLTerm: Sendable, Equatable, Hashable {
    case variable(String)
    case iri(String)
    case literal(Literal)
    case blankNode(String)
    case tripleTerm(subject: SPARQLTerm, predicate: SPARQLTerm, object: SPARQLTerm)
    /// Reified triple (SPARQL 1.2) — << subject predicate object ~reifier >>
    case reifiedTriple(subject: SPARQLTerm, predicate: SPARQLTerm, object: SPARQLTerm, reifier: SPARQLTerm)
}
