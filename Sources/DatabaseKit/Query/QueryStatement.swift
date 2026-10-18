/// QueryStatement.swift
/// Top-level query statement types
///
/// Reference:
/// - ISO/IEC 9075:2023 (SQL statements)
/// - W3C SPARQL 1.1/1.2 (Query forms)


/// Top-level query statement
public indirect enum QueryStatement: Sendable, Equatable, Hashable {
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

    /// Statement-level WITH, including writable definitions.
    case with(SQLWithStatement)

    /// Ordered conditional row mutation.
    case merge(MergeQuery)

    /// Transactional relation clearing.
    case truncate(TruncateQuery)

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
    public let columns: [String]
    public let value: Expression

    public init(column: String, value: Expression) {
        self.columns = [column]
        self.value = value
    }

    public init(columns: [String], value: Expression) {
        self.columns = columns
        self.value = value
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        ExpressionIdentity.namesEqual(lhs.columns, rhs.columns) && ExpressionIdentity.areEqual(lhs.value, rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        ExpressionIdentity.hashNames(columns, into: &hasher)
        hasher.combine(value)
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
    public let overriding: SQLIdentityOverride?
    public let onConflict: OnConflictAction?
    public let conflictTarget: SQLConflictTarget?
    public let returning: [ProjectionItem]?
    public let returningAliases: SQLReturningAliases?

    public init(
        target: TableRef,
        columns: [String]? = nil,
        source: InsertSource,
        onConflict: OnConflictAction? = nil,
        returning: [ProjectionItem]? = nil,
        overriding: SQLIdentityOverride? = nil,
        conflictTarget: SQLConflictTarget? = nil,
        returningAliases: SQLReturningAliases? = nil
    ) {
        self.overriding = overriding
        self.target = target
        self.columns = columns
        self.source = source
        self.onConflict = onConflict
        self.conflictTarget = conflictTarget
        self.returning = returning
        self.returningAliases = returningAliases
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
    public let returningAliases: SQLReturningAliases?

    public init(
        target: TableRef,
        assignments: [Assignment],
        from: DataSource? = nil,
        filter: Expression? = nil,
        returning: [ProjectionItem]? = nil,
        returningAliases: SQLReturningAliases? = nil
    ) {
        self.target = target
        self.assignments = assignments
        self.from = from
        self.filter = filter
        self.returning = returning
        self.returningAliases = returningAliases
    }
}

/// DELETE query
public struct DeleteQuery: Sendable, Equatable, Hashable {
    public let target: TableRef
    public let using: DataSource?
    public let filter: Expression?
    public let returning: [ProjectionItem]?
    public let returningAliases: SQLReturningAliases?

    public init(
        target: TableRef,
        using: DataSource? = nil,
        filter: Expression? = nil,
        returning: [ProjectionItem]? = nil,
        returningAliases: SQLReturningAliases? = nil
    ) {
        self.target = target
        self.using = using
        self.filter = filter
        self.returning = returning
        self.returningAliases = returningAliases
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
        allStatementLeavesSatisfy {
            switch $0 {
            case .select, .construct, .ask, .describe: return true
            default: return false
            }
        }
    }

    /// Returns true if this is a data modification statement
    public var isModification: Bool {
        !allStatementLeavesSatisfy {
            switch $0 {
            case .insert, .update, .delete, .merge, .truncate, .sparqlUpdate: return false
            default: return true
            }
        }
    }

    /// Returns true if this is a schema definition statement
    public var isSchemaDefinition: Bool {
        !allStatementLeavesSatisfy {
            switch $0 {
            case .createGraph, .dropGraph: return false
            default: return true
            }
        }
    }
}

private extension QueryStatement {
    enum StatementCursor {
        case statement(QueryStatement)
        case definitions([SQLNamedStatement], Int)
    }

    func allStatementLeavesSatisfy(_ predicate: (QueryStatement) -> Bool) -> Bool {
        var work: [StatementCursor] = [.statement(self)]
        while let item = work.popLast() {
            switch item {
            case .statement(.with(let value)):
                work.append(.statement(value.body))
                work.append(.definitions(value.statements, 0))
            case .statement(let value):
                if !predicate(value) { return false }
            case .definitions(let values, let index):
                if index < values.count {
                    work.append(.definitions(values, index + 1))
                    work.append(.statement(values[index].statement))
                }
            }
        }
        return true
    }
}

extension QueryStatement {
    public static func == (lhs: QueryStatement, rhs: QueryStatement) -> Bool {
        enum Comparison {
            case statement(QueryStatement, QueryStatement)
            case definitions([SQLNamedStatement], [SQLNamedStatement], Int)
        }
        var work: [Comparison] = [.statement(lhs, rhs)]
        while let item = work.popLast() {
            switch item {
            case .definitions(let left, let right, let index):
                guard left.count == right.count else { return false }
                guard index < left.count else { continue }
                let a = left[index], b = right[index]
                guard ExpressionIdentity.namedStatementMetadataEqual(a, b) else { return false }
                work.append(.definitions(left, right, index + 1))
                work.append(.statement(a.statement, b.statement))
            case .statement(let left, let right):
                switch (left, right) {
                case (.with(let a), .with(let b)):
                    guard a.recursive == b.recursive else { return false }
                    work.append(.statement(a.body, b.body))
                    work.append(.definitions(a.statements, b.statements, 0))
                case (.select(let a), .select(let b)): if a != b { return false }
                case (.insert(let a), .insert(let b)): if a != b { return false }
                case (.update(let a), .update(let b)): if a != b { return false }
                case (.delete(let a), .delete(let b)): if a != b { return false }
                case (.merge(let a), .merge(let b)): if a != b { return false }
                case (.truncate(let a), .truncate(let b)): if a != b { return false }
                case (.createGraph(let a), .createGraph(let b)): if a != b { return false }
                case (.dropGraph(let a), .dropGraph(let b)): if a != b { return false }
                case (.sparqlUpdate(let a), .sparqlUpdate(let b)): if a != b { return false }
                case (.construct(let a), .construct(let b)): if a != b { return false }
                case (.ask(let a), .ask(let b)): if a != b { return false }
                case (.describe(let a), .describe(let b)): if a != b { return false }
                default: return false
                }
            }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        var work: [StatementCursor] = [.statement(self)]
        while let item = work.popLast() {
            switch item {
            case .definitions(let values, let index):
                guard index < values.count else { continue }
                let value = values[index]
                ExpressionIdentity.hashNamedStatementMetadata(value, into: &hasher)
                work.append(.definitions(values, index + 1))
                work.append(.statement(value.statement))
            case .statement(let value):
                switch value {
                case .select(let query): hasher.combine(0); hasher.combine(query)
                case .insert(let query): hasher.combine(1); hasher.combine(query)
                case .update(let query): hasher.combine(2); hasher.combine(query)
                case .delete(let query): hasher.combine(3); hasher.combine(query)
                case .createGraph(let query): hasher.combine(4); hasher.combine(query)
                case .dropGraph(let query): hasher.combine(5); hasher.combine(query)
                case .sparqlUpdate(let query): hasher.combine(6); hasher.combine(query)
                case .construct(let query): hasher.combine(7); hasher.combine(query)
                case .ask(let query): hasher.combine(8); hasher.combine(query)
                case .describe(let query): hasher.combine(9); hasher.combine(query)
                case .with(let query):
                    hasher.combine(10); hasher.combine(query.recursive); hasher.combine(query.statements.count)
                    work.append(.statement(query.body)); work.append(.definitions(query.statements, 0))
                case .merge(let query): hasher.combine(11); hasher.combine(query)
                case .truncate(let query): hasher.combine(12); hasher.combine(query)
                }
            }
        }
    }
}
