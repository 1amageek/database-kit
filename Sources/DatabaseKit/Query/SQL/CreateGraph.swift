/// CreateGraph.swift
/// SQL/PGQ CREATE PROPERTY GRAPH statement types
///
/// Reference:
/// - ISO/IEC 9075-16:2023 (SQL/PGQ)


// Note: Core CreateGraphStatement, VertexTableDefinition, EdgeTableDefinition,
// VertexReference, LabelExpression, and PropertiesSpec types are defined in QueryStatement.swift
// This file provides additional utilities for graph creation.

// MARK: - CreateGraphStatement Builders

extension CreateGraphStatement {
    /// Create a simple graph from a single vertex and edge table
    public static func simple(
        name: String,
        vertexTable: String,
        vertexKey: String,
        edgeTable: String,
        sourceKey: String,
        targetKey: String
    ) -> CreateGraphStatement {
        CreateGraphStatement(
            graphName: name,
            vertexTables: [
                VertexTableDefinition(
                    tableName: vertexTable,
                    keyColumns: [vertexKey]
                )
            ],
            edgeTables: [
                EdgeTableDefinition(
                    tableName: edgeTable,
                    keyColumns: [sourceKey, targetKey],
                    sourceVertex: VertexReference(
                        tableName: vertexTable,
                        keyColumns: [KeyColumnMapping(source: sourceKey, target: vertexKey)]
                    ),
                    destinationVertex: VertexReference(
                        tableName: vertexTable,
                        keyColumns: [KeyColumnMapping(source: targetKey, target: vertexKey)]
                    )
                )
            ]
        )
    }

    /// Add IF NOT EXISTS modifier
    public func ifNotExists(_ flag: Bool = true) -> CreateGraphStatement {
        CreateGraphStatement(
            graphName: graphName,
            ifNotExists: flag,
            vertexTables: vertexTables,
            edgeTables: edgeTables
        )
    }
}

// MARK: - VertexTableDefinition Builders

extension VertexTableDefinition {
    /// Create a vertex table with labeled vertices
    public static func labeled(
        table: String,
        key: String,
        label: String
    ) -> VertexTableDefinition {
        VertexTableDefinition(
            tableName: table,
            keyColumns: [key],
            labelExpression: .single(label)
        )
    }

    /// Create a vertex table with label from column
    public static func dynamicLabel(
        table: String,
        key: String,
        labelColumn: String
    ) -> VertexTableDefinition {
        VertexTableDefinition(
            tableName: table,
            keyColumns: [key],
            labelExpression: .column(labelColumn)
        )
    }

    /// Set the alias for this vertex table
    public func `as`(_ alias: String) -> VertexTableDefinition {
        VertexTableDefinition(
            tableName: tableName,
            alias: alias,
            keyColumns: keyColumns,
            labelExpression: labelExpression,
            propertiesSpec: propertiesSpec
        )
    }

    /// Set the properties specification
    public func properties(_ spec: PropertiesSpec) -> VertexTableDefinition {
        VertexTableDefinition(
            tableName: tableName,
            alias: alias,
            keyColumns: keyColumns,
            labelExpression: labelExpression,
            propertiesSpec: spec
        )
    }
}

// MARK: - EdgeTableDefinition Builders

extension EdgeTableDefinition {
    /// Create an edge table with a single label
    public static func labeled(
        table: String,
        key: [String],
        from source: VertexReference,
        to destination: VertexReference,
        label: String
    ) -> EdgeTableDefinition {
        EdgeTableDefinition(
            tableName: table,
            keyColumns: key,
            sourceVertex: source,
            destinationVertex: destination,
            labelExpression: .single(label)
        )
    }

    /// Set the alias for this edge table
    public func `as`(_ alias: String) -> EdgeTableDefinition {
        EdgeTableDefinition(
            tableName: tableName,
            alias: alias,
            keyColumns: keyColumns,
            sourceVertex: sourceVertex,
            destinationVertex: destinationVertex,
            labelExpression: labelExpression,
            propertiesSpec: propertiesSpec
        )
    }

    /// Set the properties specification
    public func properties(_ spec: PropertiesSpec) -> EdgeTableDefinition {
        EdgeTableDefinition(
            tableName: tableName,
            alias: alias,
            keyColumns: keyColumns,
            sourceVertex: sourceVertex,
            destinationVertex: destinationVertex,
            labelExpression: labelExpression,
            propertiesSpec: spec
        )
    }
}

// MARK: - VertexReference Builders

extension VertexReference {
    /// Create a simple vertex reference with a single key column
    public static func simple(table: String, sourceKey: String, targetKey: String) -> VertexReference {
        VertexReference(
            tableName: table,
            keyColumns: [KeyColumnMapping(source: sourceKey, target: targetKey)]
        )
    }

    /// Create a vertex reference with multiple key columns (composite key)
    public static func composite(table: String, keys: [KeyColumnMapping]) -> VertexReference {
        VertexReference(tableName: table, keyColumns: keys)
    }
}

// MARK: - Graph Schema Validation

extension CreateGraphStatement {
    /// Validate the graph schema
    public func validate() -> [GraphSchemaError] {
        var errors: [GraphSchemaError] = []

        // Check for duplicate vertex table names/aliases
        var vertexNames = Set<String>()
        for vertex in vertexTables {
            let name = vertex.alias ?? vertex.tableName
            if vertexNames.contains(name) {
                errors.append(.duplicateVertexTable(name))
            }
            vertexNames.insert(name)
        }

        // Check for duplicate edge table names/aliases
        var edgeNames = Set<String>()
        for edge in edgeTables {
            let name = edge.alias ?? edge.tableName
            if edgeNames.contains(name) {
                errors.append(.duplicateEdgeTable(name))
            }
            edgeNames.insert(name)
        }

        // Check that edge tables reference valid vertex tables
        for edge in edgeTables {
            let sourceName = edge.sourceVertex.tableName
            if !vertexTables.contains(where: { ($0.alias ?? $0.tableName) == sourceName || $0.tableName == sourceName }) {
                errors.append(.invalidVertexReference(edge: edge.tableName, vertex: sourceName))
            }

            let destName = edge.destinationVertex.tableName
            if !vertexTables.contains(where: { ($0.alias ?? $0.tableName) == destName || $0.tableName == destName }) {
                errors.append(.invalidVertexReference(edge: edge.tableName, vertex: destName))
            }
        }

        // Check for empty key columns
        for vertex in vertexTables {
            if vertex.keyColumns.isEmpty {
                errors.append(.emptyKeyColumns(table: vertex.tableName))
            }
        }

        for edge in edgeTables {
            if edge.keyColumns.isEmpty {
                errors.append(.emptyKeyColumns(table: edge.tableName))
            }
        }

        return errors
    }
}

/// Graph schema validation errors
public enum GraphSchemaError: Error, Sendable, Equatable {
    case duplicateVertexTable(String)
    case duplicateEdgeTable(String)
    case invalidVertexReference(edge: String, vertex: String)
    case emptyKeyColumns(table: String)
    case keyColumnMismatch(edge: String, expectedCount: Int, actualCount: Int)
}

// MARK: - Graph Schema Builder (Fluent API)

/// Builder for creating property graph schemas
public struct GraphSchemaBuilder: Sendable {
    private let name: String
    private var vertexTables: [VertexTableDefinition] = []
    private var edgeTables: [EdgeTableDefinition] = []
    private var ifNotExists: Bool = false

    public init(name: String) {
        self.name = name
    }

    /// Add IF NOT EXISTS modifier
    public func ifNotExists(_ flag: Bool = true) -> GraphSchemaBuilder {
        var builder = self
        builder.ifNotExists = flag
        return builder
    }

    /// Add a vertex table
    public func vertex(_ definition: VertexTableDefinition) -> GraphSchemaBuilder {
        var builder = self
        builder.vertexTables.append(definition)
        return builder
    }

    /// Add a vertex table with simple parameters
    public func vertex(
        table: String,
        key: String,
        label: String? = nil
    ) -> GraphSchemaBuilder {
        var builder = self
        builder.vertexTables.append(
            VertexTableDefinition(
                tableName: table,
                keyColumns: [key],
                labelExpression: label.map { .single($0) }
            )
        )
        return builder
    }

    /// Add an edge table
    public func edge(_ definition: EdgeTableDefinition) -> GraphSchemaBuilder {
        var builder = self
        builder.edgeTables.append(definition)
        return builder
    }

    /// Add an edge table with simple parameters
    public func edge(
        table: String,
        sourceTable: String,
        sourceKey: String,
        destinationTable: String,
        destinationKey: String,
        label: String? = nil
    ) -> GraphSchemaBuilder {
        var builder = self
        builder.edgeTables.append(
            EdgeTableDefinition(
                tableName: table,
                keyColumns: [sourceKey, destinationKey],
                sourceVertex: VertexReference(
                    tableName: sourceTable,
                    keyColumns: [KeyColumnMapping(source: sourceKey, target: "id")]
                ),
                destinationVertex: VertexReference(
                    tableName: destinationTable,
                    keyColumns: [KeyColumnMapping(source: destinationKey, target: "id")]
                ),
                labelExpression: label.map { .single($0) }
            )
        )
        return builder
    }

    /// Build the CREATE PROPERTY GRAPH statement
    public func build() -> CreateGraphStatement {
        CreateGraphStatement(
            graphName: name,
            ifNotExists: ifNotExists,
            vertexTables: vertexTables,
            edgeTables: edgeTables
        )
    }
}

// MARK: - Convenience

extension CreateGraphStatement {
    /// Create a builder for this graph schema
    public static func builder(name: String) -> GraphSchemaBuilder {
        GraphSchemaBuilder(name: name)
    }
}
