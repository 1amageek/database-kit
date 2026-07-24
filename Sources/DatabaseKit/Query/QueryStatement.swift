/// QueryStatement.swift
/// Top-level query statement types
///
/// Reference:
/// - ISO/IEC 9075:2023 (SQL statements)
/// - W3C SPARQL 1.1/1.2 (Query forms)


/// Top-level query statement
public enum QueryStatement: Sendable, Equatable, Hashable {
    // MARK: - Data Retrieval

    /// SELECT query (SQL / SPARQL)
    case select(SelectQuery)

    // MARK: - Data Modification (SQL)

    /// INSERT statement
    case insert(InsertQuery)

    /// UPDATE statement
    case update(UpdateQuery)

    /// DELETE statement
    case delete(DeleteQuery)

    // MARK: - Graph Definition (SQL/PGQ)

    /// CREATE PROPERTY GRAPH statement
    case createGraph(CreateGraphStatement)

    /// DROP PROPERTY GRAPH statement
    case dropGraph(String)

    // MARK: - SPARQL Update

    /// A non-empty, ordered SPARQL Update request.
    case sparqlUpdate(SPARQLUpdateRequest)

    // MARK: - SPARQL Query Forms

    /// SPARQL CONSTRUCT
    case construct(ConstructQuery)

    /// SPARQL ASK
    case ask(AskQuery)

    /// SPARQL DESCRIBE
    case describe(DescribeQuery)
}

// MARK: - Common Wrapper Types

/// Column assignment (SET column = value)
public struct Assignment: Sendable, Equatable, Hashable {
    public let column: String
    public let value: Expression

    public init(column: String, value: Expression) {
        self.column = column
        self.value = value
    }
}

/// Key column mapping (source → target)
public struct KeyColumnMapping: Sendable, Equatable, Hashable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

// MARK: - SQL DML Statements

/// INSERT query
public struct InsertQuery: Sendable, Equatable, Hashable {
    public let target: TableRef
    public let columns: [String]?
    public let source: InsertSource
    public let onConflict: OnConflictAction?
    public let returning: [ProjectionItem]?

    public init(
        target: TableRef,
        columns: [String]? = nil,
        source: InsertSource,
        onConflict: OnConflictAction? = nil,
        returning: [ProjectionItem]? = nil
    ) {
        self.target = target
        self.columns = columns
        self.source = source
        self.onConflict = onConflict
        self.returning = returning
    }
}

/// Source for INSERT
public enum InsertSource: Sendable, Equatable, Hashable {
    /// VALUES (v1, v2), (v3, v4)
    case values([[Expression]])

    /// INSERT ... SELECT
    case select(SelectQuery)

    /// DEFAULT VALUES
    case defaultValues
}

/// ON CONFLICT action
public enum OnConflictAction: Sendable, Equatable, Hashable {
    /// DO NOTHING
    case doNothing

    /// DO UPDATE SET ...
    case doUpdate(assignments: [Assignment], where: Expression?)
}

/// UPDATE query
public struct UpdateQuery: Sendable, Equatable, Hashable {
    public let target: TableRef
    public let assignments: [Assignment]
    public let from: DataSource?
    public let filter: Expression?
    public let returning: [ProjectionItem]?

    public init(
        target: TableRef,
        assignments: [Assignment],
        from: DataSource? = nil,
        filter: Expression? = nil,
        returning: [ProjectionItem]? = nil
    ) {
        self.target = target
        self.assignments = assignments
        self.from = from
        self.filter = filter
        self.returning = returning
    }
}

/// DELETE query
public struct DeleteQuery: Sendable, Equatable, Hashable {
    public let target: TableRef
    public let using: DataSource?
    public let filter: Expression?
    public let returning: [ProjectionItem]?

    public init(
        target: TableRef,
        using: DataSource? = nil,
        filter: Expression? = nil,
        returning: [ProjectionItem]? = nil
    ) {
        self.target = target
        self.using = using
        self.filter = filter
        self.returning = returning
    }
}

// MARK: - SQL/PGQ Graph Definition

/// CREATE PROPERTY GRAPH statement
public struct CreateGraphStatement: Sendable, Equatable, Hashable {
    public let graphName: String
    public let ifNotExists: Bool
    public let vertexTables: [VertexTableDefinition]
    public let edgeTables: [EdgeTableDefinition]

    public init(
        graphName: String,
        ifNotExists: Bool = false,
        vertexTables: [VertexTableDefinition],
        edgeTables: [EdgeTableDefinition]
    ) {
        self.graphName = graphName
        self.ifNotExists = ifNotExists
        self.vertexTables = vertexTables
        self.edgeTables = edgeTables
    }
}

/// Vertex table definition
public struct VertexTableDefinition: Sendable, Equatable, Hashable {
    public let tableName: String
    public let alias: String?
    public let keyColumns: [String]
    public let labelExpression: LabelExpression?
    public let propertiesSpec: PropertiesSpec?

    public init(
        tableName: String,
        alias: String? = nil,
        keyColumns: [String],
        labelExpression: LabelExpression? = nil,
        propertiesSpec: PropertiesSpec? = nil
    ) {
        self.tableName = tableName
        self.alias = alias
        self.keyColumns = keyColumns
        self.labelExpression = labelExpression
        self.propertiesSpec = propertiesSpec
    }
}

/// Edge table definition
public struct EdgeTableDefinition: Sendable, Equatable, Hashable {
    public let tableName: String
    public let alias: String?
    public let keyColumns: [String]
    public let sourceVertex: VertexReference
    public let destinationVertex: VertexReference
    public let labelExpression: LabelExpression?
    public let propertiesSpec: PropertiesSpec?

    public init(
        tableName: String,
        alias: String? = nil,
        keyColumns: [String],
        sourceVertex: VertexReference,
        destinationVertex: VertexReference,
        labelExpression: LabelExpression? = nil,
        propertiesSpec: PropertiesSpec? = nil
    ) {
        self.tableName = tableName
        self.alias = alias
        self.keyColumns = keyColumns
        self.sourceVertex = sourceVertex
        self.destinationVertex = destinationVertex
        self.labelExpression = labelExpression
        self.propertiesSpec = propertiesSpec
    }
}

/// Vertex reference (for edge source/destination)
public struct VertexReference: Sendable, Equatable, Hashable {
    public let tableName: String
    public let keyColumns: [KeyColumnMapping]

    public init(tableName: String, keyColumns: [KeyColumnMapping]) {
        self.tableName = tableName
        self.keyColumns = keyColumns
    }
}

/// Label expression
public indirect enum LabelExpression: Sendable, Equatable, Hashable {
    case single(String)
    case column(String)
    case or([LabelExpression])
    case and([LabelExpression])
}

/// Properties specification
public enum PropertiesSpec: Sendable, Equatable, Hashable {
    /// All properties
    case all

    /// No properties
    case none

    /// Specific columns
    case columns([String])

    /// All except specified columns
    case allExcept([String])
}

// MARK: - SPARQL Query Forms

/// SPARQL CONSTRUCT query
public struct ConstructQuery: Sendable, Equatable, Hashable {
    public let template: [TriplePattern]
    public let pattern: GraphPattern
    public let dataset: SPARQLDataset
    public let modifiers: SPARQLSolutionModifiers

    public init(
        template: [TriplePattern],
        pattern: GraphPattern,
        dataset: SPARQLDataset = .implicit,
        modifiers: SPARQLSolutionModifiers = .none
    ) {
        self.template = template
        self.pattern = pattern
        self.dataset = dataset
        self.modifiers = modifiers
    }
}

/// SPARQL ASK query
public struct AskQuery: Sendable, Equatable, Hashable {
    public let pattern: GraphPattern
    public let dataset: SPARQLDataset
    public let modifiers: SPARQLSolutionModifiers

    public init(
        pattern: GraphPattern,
        dataset: SPARQLDataset = .implicit,
        modifiers: SPARQLSolutionModifiers = .none
    ) {
        self.pattern = pattern
        self.dataset = dataset
        self.modifiers = modifiers
    }
}

/// SPARQL DESCRIBE query
public struct DescribeQuery: Sendable, Equatable, Hashable {
    public let selection: DescribeSelection
    public let pattern: GraphPattern?
    public let dataset: SPARQLDataset
    public let modifiers: SPARQLSolutionModifiers

    public init(
        selection: DescribeSelection,
        pattern: GraphPattern? = nil,
        dataset: SPARQLDataset = .implicit,
        modifiers: SPARQLSolutionModifiers = .none
    ) {
        self.selection = selection
        self.pattern = pattern
        self.dataset = dataset
        self.modifiers = modifiers
    }
}

// MARK: - Statement Analysis

extension QueryStatement {
    /// Returns true if this is a read-only statement
    public var isReadOnly: Bool {
        switch self {
        case .select, .construct, .ask, .describe:
            return true
        default:
            return false
        }
    }

    /// Returns true if this is a data modification statement
    public var isModification: Bool {
        switch self {
        case .insert, .update, .delete, .sparqlUpdate:
            return true
        default:
            return false
        }
    }

    /// Returns true if this is a schema definition statement
    public var isSchemaDefinition: Bool {
        switch self {
        case .createGraph, .dropGraph:
            return true
        default:
            return false
        }
    }
}
