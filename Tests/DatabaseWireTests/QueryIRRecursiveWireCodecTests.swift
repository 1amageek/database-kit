import DatabaseTypes
@testable import DatabaseWire
import DatabaseKit
import Testing

@Suite("QueryIR recursive wire codec")
struct QueryIRRecursiveWireCodecTests {
    @Test("recursive value tags retain canonical byte order")
    func canonicalByteOrderIsStable() throws {
        let literal = Literal.array([
            .int(42),
            .array([.null]),
        ])
        let literalBytes = try encodeLiteral(literal, limits: .default)
        #expect(
            literalBytes == ByteString([
                8, 2, 0, 0, 0,
                2, 42, 0, 0, 0, 0, 0, 0, 0,
                8, 1, 0, 0, 0,
                0,
            ])
        )

        let dataType = DataType.array(
            .array(.decimal(precision: 12, scale: 3))
        )
        let dataTypeBytes = try encodeDataType(dataType, limits: .default)
        #expect(
            dataTypeBytes == ByteString([
                20, 20, 6,
                1, 12, 0, 0, 0, 0, 0, 0, 0,
                1, 3, 0, 0, 0, 0, 0, 0, 0,
            ])
        )

        let labelExpression = LabelExpression.and([
            .single("a"),
            .column("b"),
            .or([]),
        ])
        let labelExpressionBytes = try encodeLabelExpression(
            labelExpression,
            limits: .default
        )
        #expect(
            labelExpressionBytes == ByteString([
                3, 3, 0, 0, 0,
                0, 1, 0, 0, 0, 97,
                1, 1, 0, 0, 0, 98,
                2, 0, 0, 0, 0,
            ])
        )
        #expect(
            try decodeLabelExpression(
                labelExpressionBytes,
                limits: .default
            ) == labelExpression
        )
    }

    @Test("literal arrays traverse depth 320 iteratively")
    func deepLiteralArraysRoundTripCanonically() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        var literal = Literal.int(7)
        for _ in 0..<320 {
            literal = .array([literal])
        }

        let encoded = try encodeLiteral(literal, limits: limits)
        let decoded = try decodeLiteral(encoded, limits: limits)
        let reencoded = try encodeLiteral(decoded, limits: limits)

        #expect(reencoded == encoded)
    }

    @Test("literal arrays reject the exact first excessive depth")
    func deepLiteralArraysEnforceMaximumDepth() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        var literal = Literal.null
        for _ in 0..<320 {
            literal = .array([literal])
        }
        let encoded = try encodeLiteral(literal, limits: permissiveLimits)
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        #expect(throws: expected) {
            _ = try encodeLiteral(literal, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodeLiteral(encoded, limits: boundedLimits)
        }
    }

    @Test("array data types traverse depth 320 iteratively")
    func deepArrayDataTypesRoundTripCanonically() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        var dataType = DataType.text
        for _ in 0..<320 {
            dataType = .array(dataType)
        }

        let encoded = try encodeDataType(dataType, limits: limits)
        let decoded = try decodeDataType(encoded, limits: limits)
        let reencoded = try encodeDataType(decoded, limits: limits)

        #expect(reencoded == encoded)
    }

    @Test("array data types reject the exact first excessive depth")
    func deepArrayDataTypesEnforceMaximumDepth() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        var dataType = DataType.uuid
        for _ in 0..<320 {
            dataType = .array(dataType)
        }
        let encoded = try encodeDataType(dataType, limits: permissiveLimits)
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        #expect(throws: expected) {
            _ = try encodeDataType(dataType, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodeDataType(encoded, limits: boundedLimits)
        }
    }

    @Test("label expressions traverse depth 320 through the statement codec")
    func deepLabelExpressionsRoundTripCanonically() throws {
        let limits = try wireLimits(maximumNestingDepth: 512)
        let statement = makeCreateGraphStatement(
            labelExpression: deepLabelExpression(depth: 320)
        )

        let encoded = try QueryIRWireCodec.encode(statement, limits: limits)
        let decoded = try QueryIRWireCodec.decode(encoded, limits: limits)
        let reencoded = try QueryIRWireCodec.encode(decoded, limits: limits)

        #expect(reencoded == encoded)
    }

    @Test("label expressions reject the exact first excessive depth")
    func deepLabelExpressionsEnforceMaximumDepth() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 512)
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        let statement = makeCreateGraphStatement(
            labelExpression: deepLabelExpression(depth: 320)
        )
        let encoded = try QueryIRWireCodec.encode(
            statement,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )

        #expect(throws: expected) {
            _ = try QueryIRWireCodec.encode(
                statement,
                limits: boundedLimits
            )
        }
        #expect(throws: expected) {
            _ = try QueryIRWireCodec.decode(
                encoded,
                limits: boundedLimits
            )
        }
    }

    @Test("label expression collections preserve exact count failures")
    func labelExpressionCollectionsEnforceCountLimit() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 64)
        let boundedLimits = try wireLimits(
            maximumCollectionCount: 1,
            maximumNestingDepth: 64
        )
        let expression = LabelExpression.or([
            .single("a"),
            .column("b"),
        ])
        let encoded = try encodeLabelExpression(
            expression,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.collectionTooLarge(
            actual: 2,
            maximum: 1
        )

        #expect(throws: expected) {
            _ = try encodeLabelExpression(expression, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodeLabelExpression(encoded, limits: boundedLimits)
        }
    }

    @Test("label expressions preserve exact object budget failures")
    func labelExpressionsEnforceObjectBudget() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 64)
        let boundedLimits = try wireLimits(
            maximumNestingDepth: 64,
            maximumObjectCount: 2
        )
        let expression = LabelExpression.and([.column("kind")])
        let encoded = try encodeLabelExpression(
            expression,
            limits: permissiveLimits
        )
        let expected = DatabaseWireError.objectBudgetExceeded(
            actual: 3,
            maximum: 2
        )

        #expect(throws: expected) {
            _ = try encodeLabelExpression(expression, limits: boundedLimits)
        }
        #expect(throws: expected) {
            _ = try decodeLabelExpression(encoded, limits: boundedLimits)
        }
    }

    @Test("the complete core SCC traverses one shared iterative stack")
    func deepCoreSCCRoundTripsCanonically() throws {
        let permissiveLimits = try wireLimits(maximumNestingDepth: 1_024)
        let boundedLimits = try wireLimits(maximumNestingDepth: 64)
        var expression = Expression.literal(.int(1))
        for _ in 0..<128 {
            expression = .subquery(
                SelectQuery(
                    projection: .all,
                    source: .graphPattern(
                        .filter(.basic([]), expression)
                    )
                )
            )
        }
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(expression, alias: "value"),
                ]),
                source: .graphPattern(.basic([]))
            )
        )

        let encoded = try QueryIRWireCodec.encode(
            statement,
            limits: permissiveLimits
        )
        let decoded = try QueryIRWireCodec.decode(
            encoded,
            limits: permissiveLimits
        )
        let reencoded = try QueryIRWireCodec.encode(
            decoded,
            limits: permissiveLimits
        )
        #expect(reencoded == encoded)

        let expected = DatabaseWireError.nestingTooDeep(
            actual: 65,
            maximum: 64
        )
        #expect(throws: expected) {
            _ = try QueryIRWireCodec.encode(
                statement,
                limits: boundedLimits
            )
        }
        #expect(throws: expected) {
            _ = try QueryIRWireCodec.decode(
                encoded,
                limits: boundedLimits
            )
        }
    }

    @Test("wide SELECT collections preserve canonical order")
    func wideSelectCollectionsRoundTripCanonically() throws {
        let width = 256
        let limits = try wideWireLimits()
        let arguments = (0..<width).map {
            Expression.literal(.int(Int64($0)))
        }
        let pairs = (0..<width).map {
            CaseWhenPair(
                condition: .equal(
                    .literal(.int(Int64($0))),
                    .literal(.int(Int64($0)))
                ),
                result: .literal(.string("case-\($0)"))
            )
        }

        var projectionItems: [ProjectionItem] = []
        projectionItems.reserveCapacity(width)
        for index in 0..<width {
            let expression: Expression
            switch index {
            case 0:
                expression = .function(
                    FunctionCall(
                        name: "wide_function",
                        arguments: arguments,
                        distinct: true
                    )
                )
            case 1:
                expression = .caseWhen(
                    cases: pairs,
                    elseResult: .literal(.string("fallback"))
                )
            case 2:
                expression = .coalesce(arguments)
            default:
                expression = .literal(.int(Int64(index)))
            }
            projectionItems.append(
                ProjectionItem(expression, alias: "projection_\(index)")
            )
        }

        let orderBy = (0..<width).map {
            SortKey(
                .literal(.int(Int64($0))),
                direction: $0.isMultiple(of: 2) ? .ascending : .descending,
                nulls: $0.isMultiple(of: 3) ? .first : .last
            )
        }
        let subqueries = (0..<width).map {
            NamedSubquery(
                name: "subquery_\($0)",
                columns: ["column_\($0)"],
                query: SelectQuery(
                    projection: .all,
                    source: .table(TableRef("subquery_table_\($0)"))
                ),
                materialized: $0.isMultiple(of: 2)
                    ? .materialized
                    : .notMaterialized
            )
        }
        let unionSources = (0..<width).map {
            DataSource.table(TableRef("union_table_\($0)"))
        }
        let unionAllSources = (0..<width).map {
            DataSource.table(TableRef("union_all_table_\($0)"))
        }
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items(projectionItems),
                source: .intersect([
                    .union(unionSources),
                    .unionAll(unionAllSources),
                ]),
                filter: .caseWhen(cases: [], elseResult: nil),
                groupBy: arguments,
                having: .coalesce(arguments),
                orderBy: orderBy,
                subqueries: subqueries
            )
        )

        try expectCanonicalRoundTrip(statement, limits: limits)
    }

    @Test("wide graph-table collections preserve canonical order")
    func wideGraphTableCollectionsRoundTripCanonically() throws {
        let width = 256
        let limits = try wideWireLimits()
        let properties = (0..<width).map {
            PropertyBinding(
                key: "property_\($0)",
                value: .literal(.int(Int64($0)))
            )
        }
        let alternatives = (0..<width).map {
            PathPattern(
                pathVariable: "alternative_\($0)",
                elements: [
                    .node(NodePattern(variable: "alternative_node_\($0)")),
                ]
            )
        }

        var primaryElements: [PathElement] = [
            .node(
                NodePattern(
                    variable: "root",
                    labels: ["Root"],
                    properties: properties
                )
            ),
        ]
        primaryElements.reserveCapacity(width + 1)
        for index in 1..<width {
            if index.isMultiple(of: 2) {
                primaryElements.append(
                    .node(NodePattern(variable: "node_\(index)"))
                )
            } else {
                primaryElements.append(
                    .edge(
                        EdgePattern(
                            variable: "edge_\(index)",
                            direction: .outgoing
                        )
                    )
                )
            }
        }
        primaryElements.append(.alternation(alternatives))

        var paths: [PathPattern] = [
            PathPattern(
                pathVariable: "primary",
                elements: primaryElements,
                mode: .trail
            ),
        ]
        paths.reserveCapacity(width)
        for index in 1..<width {
            paths.append(
                PathPattern(
                    pathVariable: "path_\(index)",
                    elements: [
                        .node(NodePattern(variable: "path_node_\(index)")),
                    ],
                    mode: .walk
                )
            )
        }

        let columns = (0..<width).map {
            GraphTableColumn(
                expression: .literal(.int(Int64($0))),
                alias: "column_\($0)"
            )
        }
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphTable(
                    GraphTableSource(
                        graphName: "wide_graph",
                        matchPattern: MatchPattern(
                            paths: paths,
                            where: .literal(.bool(true))
                        ),
                        columns: columns,
                        alias: "wide_match"
                    )
                )
            )
        )

        try expectCanonicalRoundTrip(statement, limits: limits)
    }

    @Test("wide SPARQL group collections preserve canonical order")
    func wideGraphGroupCollectionsRoundTripCanonically() throws {
        let width = 256
        let limits = try wideWireLimits()
        let groupExpressions = (0..<width).map {
            Expression.literal(.string("group_\($0)"))
        }
        let aggregates = (0..<width).map {
            AggregateBinding(
                variable: "aggregate_\($0)",
                aggregate: .sum(
                    .literal(.int(Int64($0))),
                    distinct: $0.isMultiple(of: 2)
                )
            )
        }
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .all,
                source: .graphPattern(
                    .groupBy(
                        .basic([]),
                        expressions: groupExpressions,
                        aggregates: aggregates
                    )
                )
            )
        )

        try expectCanonicalRoundTrip(statement, limits: limits)
    }

    private func encodeLiteral(
        _ literal: Literal,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try QueryIRWireCodec.encodeLiteral(literal, into: &writer)
        }
    }

    private func decodeLiteral(
        _ bytes: ByteString,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> Literal {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let literal = try QueryIRWireCodec.decodeLiteral(from: &reader)
        try reader.ensureFullyRead()
        return literal
    }

    private func encodeDataType(
        _ dataType: DataType,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try QueryIRWireCodec.encodeDataType(dataType, into: &writer)
        }
    }

    private func decodeDataType(
        _ bytes: ByteString,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> DataType {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let dataType = try QueryIRWireCodec.decodeDataType(from: &reader)
        try reader.ensureFullyRead()
        return dataType
    }

    private func encodeLabelExpression(
        _ expression: LabelExpression,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try QueryIRLabelExpressionWireCodec.encode(
                expression,
                into: &writer
            )
        }
    }

    private func decodeLabelExpression(
        _ bytes: ByteString,
        limits: DatabaseWireLimits
    ) throws(DatabaseWireError) -> LabelExpression {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let expression = try QueryIRLabelExpressionWireCodec.decode(
            from: &reader
        )
        try reader.ensureFullyRead()
        return expression
    }

    private func deepLabelExpression(depth: Int) -> LabelExpression {
        var expression = LabelExpression.single("person")
        for index in 0..<depth {
            if index.isMultiple(of: 2) {
                expression = .or([expression])
            } else {
                expression = .and([expression])
            }
        }
        return expression
    }

    private func makeCreateGraphStatement(
        labelExpression: LabelExpression
    ) -> QueryStatement {
        .createGraph(
            CreateGraphStatement(
                graphName: "social",
                vertexTables: [
                    VertexTableDefinition(
                        tableName: "people",
                        keyColumns: ["id"],
                        labelExpression: labelExpression
                    ),
                ],
                edgeTables: []
            )
        )
    }

    private func expectCanonicalRoundTrip(
        _ statement: QueryStatement,
        limits: DatabaseWireLimits
    ) throws {
        let encoded = try QueryIRWireCodec.encode(statement, limits: limits)
        let decoded = try QueryIRWireCodec.decode(encoded, limits: limits)
        let reencoded = try QueryIRWireCodec.encode(decoded, limits: limits)

        #expect(decoded == statement)
        #expect(reencoded == encoded)
    }

    private func wideWireLimits() throws -> DatabaseWireLimits {
        try DatabaseWireLimits(
            maximumFrameBytes: 2 * 1_024 * 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 2 * 1_024 * 1_024,
            maximumCollectionCount: 512,
            maximumNestingDepth: 256,
            maximumObjectCount: 50_000
        )
    }

    private func wireLimits(
        maximumCollectionCount: Int = 1_024,
        maximumNestingDepth: Int,
        maximumObjectCount: Int = 2_048
    ) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(
            maximumFrameBytes: 64 * 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 64 * 1_024,
            maximumCollectionCount: maximumCollectionCount,
            maximumNestingDepth: maximumNestingDepth,
            maximumObjectCount: maximumObjectCount
        )
    }
}
