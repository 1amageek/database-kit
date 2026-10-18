import DatabaseTypes
import DatabaseKit

extension QueryIRWireFormat {
    private enum StatementEncodingStep {
        case statement(QueryStatement)
        case namedStatements([SQLNamedStatement], Int)
        case end
    }

    private struct WithDecodingState {
        let recursive: Bool
        let count: Int
        var statements: [SQLNamedStatement] = []
    }

    private struct NamedStatementMetadata {
        let name: String
        let columns: [String]?
        let materialized: Materialization?
        let search: CTESearchClause?
        let cycle: CTECycleClause?
    }

    private enum StatementDecodingStep {
        case statement
        case namedStatements(WithDecodingState)
        case finishNamed(WithDecodingState, NamedStatementMetadata)
        case finishWith(WithDecodingState)
    }

    static func encodeStatement(
        _ statement: QueryStatement, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        let initialDepth = writer.currentNestingDepth
        defer { writer.abandonNestedValues(writer.currentNestingDepth - initialDepth) }
        var steps: [StatementEncodingStep] = [.statement(statement)]
        while let step = steps.popLast() {
            switch consume step {
            case .statement(let statement):
                try writer.beginNestedValue()
                steps.append(.end)
                if case .with(let query) = statement {
                    writer.writeUInt8(10)
                    writer.writeBool(query.recursive)
                    try writer.writeCount(query.statements.count)
                    steps.append(.statement(query.body))
                    steps.append(.namedStatements(query.statements, 0))
                } else {
                    try encodeStatementLeaf(statement, into: &writer)
                }
            case .namedStatements(let statements, let index):
                guard index < statements.count else { continue }
                let named = statements[index]
                try writer.writeString(named.name)
                try writeOptionalStrings(named.columns, into: &writer)
                try writeOptional(named.materialized, into: &writer) { value, writer in
                    writer.writeUInt8(value == .materialized ? 0 : 1)
                }
                try encodeCTEMetadata(search: named.search, cycle: named.cycle, into: &writer)
                steps.append(.namedStatements(statements, index + 1))
                steps.append(.statement(named.statement))
            case .end:
                try writer.endNestedValue()
            }
        }
        try validateStatementStructure(statement)
    }

    static func decodeStatement(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> QueryStatement {
        let initialDepth = reader.currentNestingDepth
        defer { reader.abandonNestedValues(reader.currentNestingDepth - initialDepth) }
        var steps: [StatementDecodingStep] = [.statement]
        var result: QueryStatement?
        while let step = steps.popLast() {
            switch consume step {
            case .statement:
                try reader.beginNestedValue()
                let tag = try reader.readUInt8()
                if tag == 10 {
                    let recursive = try reader.readBool()
                    let count = try reader.readCount()
                    steps.append(.namedStatements(WithDecodingState(recursive: recursive, count: count)))
                } else {
                    result = try decodeStatementLeaf(tag, from: &reader)
                    try reader.endNestedValue()
                }
            case .namedStatements(let state):
                if state.statements.count == state.count {
                    steps.append(.finishWith(state))
                    steps.append(.statement)
                } else {
                    let name = try reader.readString()
                    let columns = try readOptionalStrings(from: &reader)
                    let materialized: Materialization? = try readOptional(from: &reader) {
                        (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> Materialization in
                        switch try reader.readUInt8() {
                        case 0: return .materialized
                        case 1: return .notMaterialized
                        case let tag: throw .invalidValueTag(tag)
                        }
                    }
                    let metadata = try decodeCTEMetadata(from: &reader)
                    steps.append(.finishNamed(state, NamedStatementMetadata(name: name, columns: columns,
                        materialized: materialized, search: metadata.search, cycle: metadata.cycle)))
                    steps.append(.statement)
                }
            case .finishNamed(var state, let metadata):
                guard let child = result else { throw .invalidQueryIRWireState }
                state.statements.append(SQLNamedStatement(name: metadata.name, columns: metadata.columns,
                    statement: child, materialized: metadata.materialized, search: metadata.search, cycle: metadata.cycle))
                result = nil
                steps.append(.namedStatements(state))
            case .finishWith(let state):
                guard let body = result else { throw .invalidQueryIRWireState }
                result = .with(SQLWithStatement(recursive: state.recursive, statements: state.statements, body: body))
                try reader.endNestedValue()
            }
        }
        guard let result else { throw .invalidQueryIRWireState }
        try validateStatementStructure(result)
        return result
    }

    private static func validateStatementStructure(_ statement: QueryStatement) throws(DatabaseWireError) {
        switch statement {
        case .insert, .update, .delete, .with, .merge, .truncate, .ddl: break
        default: return
        }
        // Wire owns resource admission; Kit owns intrinsic statement shape admission.
        let limits = QueryStructuralLimits(maximumNestingDepth: .max, maximumRetainedBytes: .max,
            maximumTotalNodes: .max, maximumCollectionElements: .max,
            maximumBasicGraphPatterns: .max, maximumTriplePatterns: .max,
            maximumValuesRows: .max, maximumValuesVariables: .max, maximumValuesCells: .max,
            maximumReifiedTripleExpansions: .max)
        do { try QueryStructuralValidator.validate(statement, limits: limits) }
        catch { throw .invalidQueryStructure(error) }
    }

    private static func encodeStatementLeaf(_ statement: QueryStatement, into writer: inout DatabaseWireWriter) throws(DatabaseWireError) {
        switch statement {
        case .select(let query):
            writer.writeUInt8(0)
            try encodeSelectQuery(query, into: &writer)
        case .insert(let query):
            writer.writeUInt8(1)
            try encodeInsertQuery(query, into: &writer)
        case .update(let query):
            writer.writeUInt8(2)
            try encodeUpdateQuery(query, into: &writer)
        case .delete(let query):
            writer.writeUInt8(3)
            try encodeDeleteQuery(query, into: &writer)
        case .createGraph(let statement):
            writer.writeUInt8(4)
            try encodeCreateGraphStatement(statement, into: &writer)
        case .dropGraph(let name):
            writer.writeUInt8(5)
            try writer.writeString(name)
        case .sparqlUpdate(let request):
            writer.writeUInt8(6)
            try encodeSPARQLUpdateRequest(request, into: &writer)
        case .construct(let query):
            writer.writeUInt8(7)
            try writeArray(query.template, into: &writer, encode: encodeTriplePattern)
            try encodeGraphPattern(query.pattern, into: &writer)
            try encodeSPARQLDataset(query.dataset, into: &writer)
            try encodeSPARQLSolutionModifiers(query.modifiers, into: &writer)
        case .ask(let query):
            writer.writeUInt8(8)
            try encodeGraphPattern(query.pattern, into: &writer)
            try encodeSPARQLDataset(query.dataset, into: &writer)
            try encodeSPARQLSolutionModifiers(query.modifiers, into: &writer)
        case .describe(let query):
            writer.writeUInt8(9)
            try encodeDescribeSelection(query.selection, into: &writer)
            try writeOptional(query.pattern, into: &writer, encode: encodeGraphPattern)
            try encodeSPARQLDataset(query.dataset, into: &writer)
            try encodeSPARQLSolutionModifiers(query.modifiers, into: &writer)
        case .merge(let query):
            writer.writeUInt8(11)
            try encodeMergeQuery(query, into: &writer)
        case .truncate(let query):
            writer.writeUInt8(12)
            try writeArray(query.tables, into: &writer, encode: encodeTableRef)
            writer.writeUInt8(query.identity == .continue ? 0 : 1)
            writer.writeUInt8(query.references == .restrict ? 0 : 1)
        case .ddl(let statement):
            writer.writeUInt8(13)
            try encodeDDL(statement, into: &writer)
        case .with: throw .invalidQueryIRWireState
        }
    }

    private static func decodeStatementLeaf(_ tag: UInt8, from reader: inout DatabaseWireReader) throws(DatabaseWireError) -> QueryStatement {
        switch tag {
            case 0: return .select(try decodeSelectQuery(from: &reader))
            case 1: return .insert(try decodeInsertQuery(from: &reader))
            case 2: return .update(try decodeUpdateQuery(from: &reader))
            case 3: return .delete(try decodeDeleteQuery(from: &reader))
            case 4: return .createGraph(try decodeCreateGraphStatement(from: &reader))
            case 5: return .dropGraph(try reader.readString())
            case 6:
                return .sparqlUpdate(
                    try decodeSPARQLUpdateRequest(from: &reader)
                )
            case 7:
                return .construct(
                    ConstructQuery(
                        template: try readArray(from: &reader, decode: decodeTriplePattern),
                        pattern: try decodeGraphPattern(from: &reader),
                        dataset: try decodeSPARQLDataset(from: &reader),
                        modifiers: try decodeSPARQLSolutionModifiers(from: &reader)
                    )
                )
            case 8:
                return .ask(
                    AskQuery(
                        pattern: try decodeGraphPattern(from: &reader),
                        dataset: try decodeSPARQLDataset(from: &reader),
                        modifiers: try decodeSPARQLSolutionModifiers(from: &reader)
                    )
                )
            case 9:
                return .describe(
                    DescribeQuery(
                        selection: try decodeDescribeSelection(from: &reader),
                        pattern: try readOptional(from: &reader, decode: decodeGraphPattern),
                        dataset: try decodeSPARQLDataset(from: &reader),
                        modifiers: try decodeSPARQLSolutionModifiers(from: &reader)
                    )
                )
            case 13: return .ddl(try decodeDDL(from: &reader))
            case 11: return .merge(try decodeMergeQuery(from: &reader))
            case 12:
                let tables = try readArray(from: &reader, decode: decodeTableRef)
                let identity: SQLTruncateIdentity
                switch try reader.readUInt8() {
                case 0: identity = .continue
                case 1: identity = .restart
                case let tag: throw .invalidValueTag(tag)
                }
                let references: SQLTruncateReferences
                switch try reader.readUInt8() {
                case 0: references = .restrict
                case 1: references = .cascade
                case let tag: throw .invalidValueTag(tag)
                }
                return .truncate(TruncateQuery(tables: tables, identity: identity, references: references))
            case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeIdentityOverride(_ value: SQLIdentityOverride?, into writer: inout DatabaseWireWriter) {
        switch value {
        case nil: writer.writeUInt8(0)
        case .systemValue?: writer.writeUInt8(1)
        case .userValue?: writer.writeUInt8(2)
        }
    }

    private static func encodeReturningAliases(
        _ value: SQLReturningAliases, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalString(value.old, into: &writer)
        try writeOptionalString(value.new, into: &writer)
    }

    private static func decodeReturningAliases(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SQLReturningAliases {
        SQLReturningAliases(old: try readOptionalString(from: &reader), new: try readOptionalString(from: &reader))
    }

    private static func encodeConflictTarget(
        _ target: SQLConflictTarget, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch target {
        case .columns(let columns, let predicate):
            writer.writeUInt8(0)
            try writeStrings(columns, into: &writer)
            try writeOptional(predicate, into: &writer, encode: encodeExpression)
        case .constraint(let name):
            writer.writeUInt8(1)
            try writer.writeString(name)
        }
    }

    private static func decodeConflictTarget(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SQLConflictTarget {
        switch try reader.readUInt8() {
        case 0: return .columns(try readStrings(from: &reader), where: try readOptional(from: &reader, decode: decodeExpression))
        case 1: return .constraint(try reader.readString())
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeMergeQuery(
        _ query: MergeQuery, into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTableRef(query.target, into: &writer)
        try encodeDataSource(query.source, into: &writer)
        try encodeExpression(query.condition, into: &writer)
        try writeArray(query.clauses, into: &writer) {
            (clause: SQLMergeClause, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            switch clause.match {
            case .matched: writer.writeUInt8(0)
            case .notMatchedByTarget: writer.writeUInt8(1)
            case .notMatchedBySource: writer.writeUInt8(2)
            }
            try writeOptional(clause.condition, into: &writer, encode: encodeExpression)
            switch clause.action {
            case .insert(let columns, let values, let overriding):
                writer.writeUInt8(0)
                try writeOptionalStrings(columns, into: &writer)
                try writeOptional(values, into: &writer) {
                    (values: [Expression], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    try writeArray(values, into: &writer, encode: encodeExpression)
                }
                encodeIdentityOverride(overriding, into: &writer)
            case .update(let assignments):
                writer.writeUInt8(1)
                try writeArray(assignments, into: &writer, encode: encodeAssignment)
            case .delete: writer.writeUInt8(2)
            case .doNothing: writer.writeUInt8(3)
            }
        }
        try writeOptional(query.returning, into: &writer) {
            (items: [ProjectionItem], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        }
        try writeOptional(query.returningAliases, into: &writer, encode: encodeReturningAliases)
    }

    private static func decodeMergeQuery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> MergeQuery {
        let target = try decodeTableRef(from: &reader)
        let source = try decodeDataSource(from: &reader)
        let condition = try decodeExpression(from: &reader)
        let clauses: [SQLMergeClause] = try readArray(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SQLMergeClause in
            let match: SQLMergeMatch
            switch try reader.readUInt8() {
            case 0: match = .matched
            case 1: match = .notMatchedByTarget
            case 2: match = .notMatchedBySource
            case let tag: throw .invalidValueTag(tag)
            }
            let condition = try readOptional(from: &reader, decode: decodeExpression)
            let action: SQLMergeAction
            switch try reader.readUInt8() {
            case 0:
                let columns = try readOptionalStrings(from: &reader)
                let values: [Expression]? = try readOptional(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [Expression] in
                    try readArray(from: &reader, decode: decodeExpression)
                }
                action = .insert(columns: columns, values: values, overriding: try decodeIdentityOverride(from: &reader))
            case 1: action = .update(try readArray(from: &reader, decode: decodeAssignment))
            case 2: action = .delete
            case 3: action = .doNothing
            case let tag: throw .invalidValueTag(tag)
            }
            return SQLMergeClause(match: match, condition: condition, action: action)
        }
        let returning: [ProjectionItem]? = try readOptional(from: &reader) {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [ProjectionItem] in
            try readArray(from: &reader, decode: decodeProjectionItem)
        }
        let aliases = try readOptional(from: &reader, decode: decodeReturningAliases)
        return MergeQuery(target: target, source: source, condition: condition, clauses: clauses,
                          returning: returning, returningAliases: aliases)
    }

    private static func encodeInsertQuery(
        _ query: InsertQuery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTableRef(query.target, into: &writer)
        try writeOptionalStrings(query.columns, into: &writer)
        try encodeInsertSource(query.source, into: &writer)
        try writeOptional(query.onConflict, into: &writer, encode: encodeOnConflictAction)
        try writeOptional(query.returning, into: &writer) {
            (items: [ProjectionItem], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        }
        encodeIdentityOverride(query.overriding, into: &writer)
        try writeOptional(query.conflictTarget, into: &writer, encode: encodeConflictTarget)
        try writeOptional(query.returningAliases, into: &writer, encode: encodeReturningAliases)
    }

    private static func decodeInsertQuery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> InsertQuery {
        InsertQuery(
            target: try decodeTableRef(from: &reader),
            columns: try readOptionalStrings(from: &reader),
            source: try decodeInsertSource(from: &reader),
            onConflict: try readOptional(from: &reader, decode: decodeOnConflictAction),
            returning: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [ProjectionItem] in
                try readArray(from: &reader, decode: decodeProjectionItem)
            },
            overriding: try decodeIdentityOverride(from: &reader),
            conflictTarget: try readOptional(from: &reader, decode: decodeConflictTarget),
            returningAliases: try readOptional(from: &reader, decode: decodeReturningAliases)
        )
    }

    private static func decodeIdentityOverride(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SQLIdentityOverride? {
        switch try reader.readUInt8() {
        case 0: return nil
        case 1: return .systemValue
        case 2: return .userValue
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeInsertSource(
        _ source: InsertSource,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch source {
        case .values(let rows):
            writer.writeUInt8(0)
            try writeArray(rows, into: &writer) {
                (row: [Expression], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try writeArray(row, into: &writer, encode: encodeExpression)
            }
        case .select(let query):
            writer.writeUInt8(1)
            try encodeSelectQuery(query, into: &writer)
        case .defaultValues:
            writer.writeUInt8(2)
        }
    }

    private static func decodeInsertSource(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> InsertSource {
        switch try reader.readUInt8() {
        case 0:
            return .values(
                try readArray(from: &reader) {
                    (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [Expression] in
                    try readArray(from: &reader, decode: decodeExpression)
                }
            )
        case 1: return .select(try decodeSelectQuery(from: &reader))
        case 2: return .defaultValues
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeOnConflictAction(
        _ action: OnConflictAction,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch action {
        case .doNothing:
            writer.writeUInt8(0)
        case .doUpdate(let assignments, let filter):
            writer.writeUInt8(1)
            try writeArray(assignments, into: &writer, encode: encodeAssignment)
            try writeOptional(filter, into: &writer, encode: encodeExpression)
        }
    }

    private static func decodeOnConflictAction(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> OnConflictAction {
        switch try reader.readUInt8() {
        case 0: return .doNothing
        case 1:
            return .doUpdate(
                assignments: try readArray(from: &reader, decode: decodeAssignment),
                where: try readOptional(from: &reader, decode: decodeExpression)
            )
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeUpdateQuery(
        _ query: UpdateQuery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTableRef(query.target, into: &writer)
        try writeArray(query.assignments, into: &writer, encode: encodeAssignment)
        try writeOptional(query.from, into: &writer, encode: encodeDataSource)
        try writeOptional(query.filter, into: &writer, encode: encodeExpression)
        try writeOptional(query.returning, into: &writer) {
            (items: [ProjectionItem], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        }
        try writeOptional(query.returningAliases, into: &writer, encode: encodeReturningAliases)
    }

    private static func decodeUpdateQuery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> UpdateQuery {
        UpdateQuery(
            target: try decodeTableRef(from: &reader),
            assignments: try readArray(from: &reader, decode: decodeAssignment),
            from: try readOptional(from: &reader, decode: decodeDataSource),
            filter: try readOptional(from: &reader, decode: decodeExpression),
            returning: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [ProjectionItem] in
                try readArray(from: &reader, decode: decodeProjectionItem)
            },
            returningAliases: try readOptional(from: &reader, decode: decodeReturningAliases)
        )
    }

    private static func encodeDeleteQuery(
        _ query: DeleteQuery,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try encodeTableRef(query.target, into: &writer)
        try writeOptional(query.using, into: &writer, encode: encodeDataSource)
        try writeOptional(query.filter, into: &writer, encode: encodeExpression)
        try writeOptional(query.returning, into: &writer) {
            (items: [ProjectionItem], writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writeArray(items, into: &writer, encode: encodeProjectionItem)
        }
        try writeOptional(query.returningAliases, into: &writer, encode: encodeReturningAliases)
    }

    private static func decodeDeleteQuery(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> DeleteQuery {
        DeleteQuery(
            target: try decodeTableRef(from: &reader),
            using: try readOptional(from: &reader, decode: decodeDataSource),
            filter: try readOptional(from: &reader, decode: decodeExpression),
            returning: try readOptional(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> [ProjectionItem] in
                try readArray(from: &reader, decode: decodeProjectionItem)
            },
            returningAliases: try readOptional(from: &reader, decode: decodeReturningAliases)
        )
    }

    private static func encodeAssignment(
        _ assignment: Assignment,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeStrings(assignment.columns, into: &writer)
        try encodeExpression(assignment.value, into: &writer)
    }

    private static func decodeAssignment(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Assignment {
        Assignment(
            columns: try readStrings(from: &reader),
            value: try decodeExpression(from: &reader)
        )
    }

    private static func encodeCreateGraphStatement(
        _ statement: CreateGraphStatement,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(statement.graphName)
        writer.writeBool(statement.ifNotExists)
        try writeArray(statement.vertexTables, into: &writer, encode: encodeVertexTable)
        try writeArray(statement.edgeTables, into: &writer, encode: encodeEdgeTable)
    }

    private static func decodeCreateGraphStatement(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> CreateGraphStatement {
        CreateGraphStatement(
            graphName: try reader.readString(),
            ifNotExists: try reader.readBool(),
            vertexTables: try readArray(from: &reader, decode: decodeVertexTable),
            edgeTables: try readArray(from: &reader, decode: decodeEdgeTable)
        )
    }

    private static func encodeVertexTable(
        _ table: VertexTableDefinition,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(table.tableName)
        try writeOptionalString(table.alias, into: &writer)
        try writeStrings(table.keyColumns, into: &writer)
        try writeOptional(table.labelExpression, into: &writer, encode: encodeLabelExpression)
        try writeOptional(table.propertiesSpec, into: &writer, encode: encodePropertiesSpec)
    }

    private static func decodeVertexTable(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> VertexTableDefinition {
        VertexTableDefinition(
            tableName: try reader.readString(),
            alias: try readOptionalString(from: &reader),
            keyColumns: try readStrings(from: &reader),
            labelExpression: try readOptional(from: &reader, decode: decodeLabelExpression),
            propertiesSpec: try readOptional(from: &reader, decode: decodePropertiesSpec)
        )
    }

    private static func encodeEdgeTable(
        _ table: EdgeTableDefinition,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(table.tableName)
        try writeOptionalString(table.alias, into: &writer)
        try writeStrings(table.keyColumns, into: &writer)
        try encodeVertexReference(table.sourceVertex, into: &writer)
        try encodeVertexReference(table.destinationVertex, into: &writer)
        try writeOptional(table.labelExpression, into: &writer, encode: encodeLabelExpression)
        try writeOptional(table.propertiesSpec, into: &writer, encode: encodePropertiesSpec)
    }

    private static func decodeEdgeTable(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> EdgeTableDefinition {
        EdgeTableDefinition(
            tableName: try reader.readString(),
            alias: try readOptionalString(from: &reader),
            keyColumns: try readStrings(from: &reader),
            sourceVertex: try decodeVertexReference(from: &reader),
            destinationVertex: try decodeVertexReference(from: &reader),
            labelExpression: try readOptional(from: &reader, decode: decodeLabelExpression),
            propertiesSpec: try readOptional(from: &reader, decode: decodePropertiesSpec)
        )
    }

    private static func encodeVertexReference(
        _ reference: VertexReference,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeString(reference.tableName)
        try writeArray(reference.keyColumns, into: &writer) {
            (mapping: KeyColumnMapping, writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString(mapping.source)
            try writer.writeString(mapping.target)
        }
    }

    private static func decodeVertexReference(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> VertexReference {
        VertexReference(
            tableName: try reader.readString(),
            keyColumns: try readArray(from: &reader) {
                (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> KeyColumnMapping in
                KeyColumnMapping(
                    source: try reader.readString(),
                    target: try reader.readString()
                )
            }
        )
    }

    private static func encodeLabelExpression(
        _ expression: LabelExpression,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try QueryIRLabelExpressionWireCodec.encode(
            expression,
            into: &writer
        )
    }

    private static func decodeLabelExpression(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> LabelExpression {
        try QueryIRLabelExpressionWireCodec.decode(from: &reader)
    }

    private static func encodePropertiesSpec(
        _ spec: PropertiesSpec,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch spec {
        case .all: writer.writeUInt8(0)
        case .none: writer.writeUInt8(1)
        case .columns(let columns):
            writer.writeUInt8(2)
            try writeStrings(columns, into: &writer)
        case .allExcept(let columns):
            writer.writeUInt8(3)
            try writeStrings(columns, into: &writer)
        }
    }

    private static func decodePropertiesSpec(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> PropertiesSpec {
        switch try reader.readUInt8() {
        case 0: return .all
        case 1: return .none
        case 2: return .columns(try readStrings(from: &reader))
        case 3: return .allExcept(try readStrings(from: &reader))
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeSPARQLUpdateRequest(
        _ request: SPARQLUpdateRequest,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.withNestedValue {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try writer.writeCount(request.count)
            for operation in request {
                try encodeSPARQLUpdateOperation(operation, into: &writer)
            }
        }
    }

    private static func decodeSPARQLUpdateRequest(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLUpdateRequest {
        try reader.withNestedValue {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SPARQLUpdateRequest in
            let count = try reader.readCount()
            guard count > 0 else {
                throw .emptySPARQLUpdateRequest
            }

            let firstOperation = try decodeSPARQLUpdateOperation(from: &reader)
            var additionalOperations: [SPARQLUpdateOperation] = []
            additionalOperations.reserveCapacity(count - 1)
            for _ in 1..<count {
                additionalOperations.append(
                    try decodeSPARQLUpdateOperation(from: &reader)
                )
            }
            return SPARQLUpdateRequest(
                firstOperation: firstOperation,
                additionalOperations: consume additionalOperations
            )
        }
    }

    private static func encodeSPARQLUpdateOperation(
        _ operation: SPARQLUpdateOperation,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.withNestedValue {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            switch operation {
            case .insertData(let query):
                writer.writeUInt8(0)
                try writeArray(query.quads, into: &writer, encode: encodeQuad)
            case .deleteData(let query):
                writer.writeUInt8(1)
                try writeArray(query.quads, into: &writer, encode: encodeQuad)
            case .modify(let query):
                writer.writeUInt8(2)
                try encodeSPARQLModifyOperation(query, into: &writer)
            case .deleteWhere(let query):
                writer.writeUInt8(3)
                try writeArray(query.pattern, into: &writer, encode: encodeQuad)
            case .load(let query):
                writer.writeUInt8(4)
                try writeSPARQLIRI(query.source, into: &writer)
                try writeOptionalSPARQLIRI(query.destination, into: &writer)
                writer.writeBool(query.silent)
            case .clear(let query):
                writer.writeUInt8(5)
                try encodeSPARQLGraphTarget(query.target, into: &writer)
                writer.writeBool(query.silent)
            case .createGraph(let query):
                writer.writeUInt8(6)
                try writeSPARQLIRI(query.graph, into: &writer)
                writer.writeBool(query.silent)
            case .drop(let query):
                writer.writeUInt8(7)
                try encodeSPARQLGraphTarget(query.target, into: &writer)
                writer.writeBool(query.silent)
            case .graphTransfer(let query):
                writer.writeUInt8(8)
                encodeSPARQLGraphTransferOperation(query.operation, into: &writer)
                try encodeSPARQLGraphTransferEndpoint(query.source, into: &writer)
                try encodeSPARQLGraphTransferEndpoint(query.destination, into: &writer)
                writer.writeBool(query.silent)
            }
        }
    }

    private static func decodeSPARQLUpdateOperation(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLUpdateOperation {
        try reader.withNestedValue {
            (reader: inout DatabaseWireReader) throws(DatabaseWireError) -> SPARQLUpdateOperation in
            switch try reader.readUInt8() {
            case 0:
                return .insertData(
                    InsertDataQuery(
                        quads: try readArray(from: &reader, decode: decodeQuad)
                    )
                )
            case 1:
                return .deleteData(
                    DeleteDataQuery(
                        quads: try readArray(from: &reader, decode: decodeQuad)
                    )
                )
            case 2:
                return .modify(try decodeSPARQLModifyOperation(from: &reader))
            case 3:
                return .deleteWhere(
                    DeleteWhereQuery(
                        pattern: try readArray(from: &reader, decode: decodeQuad)
                    )
                )
            case 4:
                return .load(
                    LoadQuery(
                        source: try readSPARQLIRI(from: &reader),
                        destination: try readOptionalSPARQLIRI(from: &reader),
                        silent: try reader.readBool()
                    )
                )
            case 5:
                return .clear(
                    ClearQuery(
                        target: try decodeSPARQLGraphTarget(from: &reader),
                        silent: try reader.readBool()
                    )
                )
            case 6:
                return .createGraph(
                    CreateSPARQLGraphQuery(
                        graph: try readSPARQLIRI(from: &reader),
                        silent: try reader.readBool()
                    )
                )
            case 7:
                return .drop(
                    DropQuery(
                        target: try decodeSPARQLGraphTarget(from: &reader),
                        silent: try reader.readBool()
                    )
                )
            case 8:
                return .graphTransfer(
                    GraphTransferQuery(
                        operation: try decodeSPARQLGraphTransferOperation(
                            from: &reader
                        ),
                        source: try decodeSPARQLGraphTransferEndpoint(
                            from: &reader
                        ),
                        destination: try decodeSPARQLGraphTransferEndpoint(
                            from: &reader
                        ),
                        silent: try reader.readBool()
                    )
                )
            case let tag:
                throw .invalidValueTag(tag)
            }
        }
    }

    private static func encodeSPARQLModifyOperation(
        _ operation: SPARQLModifyOperation,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptionalSPARQLIRI(operation.withGraph, into: &writer)
        try encodeSPARQLModifyAction(operation.action, into: &writer)
        try writeArray(operation.using, into: &writer, encode: encodeGraphRef)
        try encodeGraphPattern(operation.wherePattern, into: &writer)
    }

    private static func decodeSPARQLModifyOperation(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLModifyOperation {
        SPARQLModifyOperation(
            withGraph: try readOptionalSPARQLIRI(from: &reader),
            action: try decodeSPARQLModifyAction(from: &reader),
            using: try readArray(from: &reader, decode: decodeGraphRef),
            wherePattern: try decodeGraphPattern(from: &reader)
        )
    }

    private static func encodeSPARQLModifyAction(
        _ action: SPARQLModifyAction,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch action {
        case .delete(let quads):
            writer.writeUInt8(0)
            try writeArray(quads, into: &writer, encode: encodeQuad)
        case .insert(let quads):
            writer.writeUInt8(1)
            try writeArray(quads, into: &writer, encode: encodeQuad)
        case .deleteAndInsert(let deleteQuads, let insertQuads):
            writer.writeUInt8(2)
            try writeArray(deleteQuads, into: &writer, encode: encodeQuad)
            try writeArray(insertQuads, into: &writer, encode: encodeQuad)
        }
    }

    private static func decodeSPARQLModifyAction(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLModifyAction {
        switch try reader.readUInt8() {
        case 0:
            return .delete(try readArray(from: &reader, decode: decodeQuad))
        case 1:
            return .insert(try readArray(from: &reader, decode: decodeQuad))
        case 2:
            return .deleteAndInsert(
                delete: try readArray(from: &reader, decode: decodeQuad),
                insert: try readArray(from: &reader, decode: decodeQuad)
            )
        case let tag:
            throw .invalidValueTag(tag)
        }
    }

    private static func encodeQuad(
        _ quad: Quad,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeOptional(quad.graph, into: &writer, encode: encodeSPARQLTerm)
        try encodeTriplePattern(quad.triple, into: &writer)
    }

    private static func decodeQuad(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> Quad {
        Quad(
            graph: try readOptional(from: &reader, decode: decodeSPARQLTerm),
            triple: try decodeTriplePattern(from: &reader)
        )
    }

    private static func encodeGraphRef(
        _ reference: GraphRef,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writeSPARQLIRI(reference.iri, into: &writer)
        writer.writeBool(reference.isNamed)
    }

    private static func decodeGraphRef(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> GraphRef {
        GraphRef(
            iri: try readSPARQLIRI(from: &reader),
            isNamed: try reader.readBool()
        )
    }

    private static func encodeSPARQLGraphTarget(
        _ target: SPARQLGraphTarget,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch target {
        case .graph(let name):
            writer.writeUInt8(0)
            try writeSPARQLIRI(name, into: &writer)
        case .default: writer.writeUInt8(1)
        case .named: writer.writeUInt8(2)
        case .all: writer.writeUInt8(3)
        }
    }

    private static func decodeSPARQLGraphTarget(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLGraphTarget {
        switch try reader.readUInt8() {
        case 0: return .graph(try readSPARQLIRI(from: &reader))
        case 1: return .default
        case 2: return .named
        case 3: return .all
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeSPARQLGraphTransferOperation(
        _ operation: SPARQLGraphTransferOperation,
        into writer: inout DatabaseWireWriter
    ) {
        switch operation {
        case .add: writer.writeUInt8(0)
        case .copy: writer.writeUInt8(1)
        case .move: writer.writeUInt8(2)
        }
    }

    private static func decodeSPARQLGraphTransferOperation(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLGraphTransferOperation {
        switch try reader.readUInt8() {
        case 0: return .add
        case 1: return .copy
        case 2: return .move
        case let tag: throw .invalidValueTag(tag)
        }
    }

    private static func encodeSPARQLGraphTransferEndpoint(
        _ endpoint: SPARQLGraphTransferEndpoint,
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        switch endpoint {
        case .default:
            writer.writeUInt8(0)
        case .graph(let iri):
            writer.writeUInt8(1)
            try writeSPARQLIRI(iri, into: &writer)
        }
    }

    private static func decodeSPARQLGraphTransferEndpoint(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) -> SPARQLGraphTransferEndpoint {
        switch try reader.readUInt8() {
        case 0: return .default
        case 1: return .graph(try readSPARQLIRI(from: &reader))
        case let tag: throw .invalidValueTag(tag)
        }
    }
}
