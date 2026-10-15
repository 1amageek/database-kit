import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Query structural validation")
struct QueryStructuralValidatorTests {

    @Test("Residual limits compose child admission without releasing cumulative usage")
    func residualLimitsComposeChildAdmission() throws {
        var ledger = QueryStructuralResourceLedger(limits: QueryStructuralLimits(
            maximumNestingDepth: 3, maximumRetainedBytes: 11,
            maximumInputTokens: 12, maximumTotalNodes: 5,
            maximumCollectionElements: 14, maximumBasicGraphPatterns: 15,
            maximumTriplePatterns: 16, maximumValuesRows: 17,
            maximumValuesVariables: 18, maximumValuesCells: 19,
            maximumReifiedTripleExpansions: 20
        ))
        try ledger.enterNesting()
        try ledger.enterNesting()
        let resources: [QueryStructuralValidationError.Resource] = [
            .retainedBytes, .inputTokens, .totalNodes, .collectionElements,
            .basicGraphPatterns, .triplePatterns, .valuesRows,
            .valuesVariables, .valuesCells, .reifiedTripleExpansions,
        ]
        for resource in resources { try ledger.consume(resource, amount: 2) }
        #expect(ledger.remainingLimits == QueryStructuralLimits(
            maximumNestingDepth: 1, maximumRetainedBytes: 9,
            maximumInputTokens: 10, maximumTotalNodes: 3,
            maximumCollectionElements: 12, maximumBasicGraphPatterns: 13,
            maximumTriplePatterns: 14, maximumValuesRows: 15,
            maximumValuesVariables: 16, maximumValuesCells: 17,
            maximumReifiedTripleExpansions: 18
        ))

        var child = QueryStructuralResourceLedger(limits: ledger.remainingLimits)
        try child.consume(.totalNodes, amount: 3)
        try child.enterNesting()
        #expect(child.remainingLimits.maximumTotalNodes == 0)
        #expect(child.remainingLimits.maximumNestingDepth == 0)
        #expect(throws: QueryStructuralValidationError.self) {
            try child.consume(.totalNodes)
        }
        #expect(throws: QueryStructuralValidationError.self) { try child.enterNesting() }
        #expect(child.remainingLimits.maximumTotalNodes == 0)
        #expect(child.remainingLimits.maximumNestingDepth == 0)
        try ledger.consume(.totalNodes, amount: 3)
        try ledger.leaveNesting()
        #expect(ledger.remainingLimits.maximumNestingDepth == 2)
        #expect(ledger.remainingLimits.maximumTotalNodes == 0)
        #expect(ledger.remainingLimits.maximumRetainedBytes == 9)

        var overflow = QueryStructuralResourceLedger(
            limits: QueryStructuralLimits(maximumRetainedBytes: .max)
        )
        try overflow.consume(.retainedBytes, amount: .max)
        #expect(throws: QueryStructuralValidationError.self) {
            try overflow.consume(.retainedBytes)
        }
        #expect(overflow.remainingLimits.maximumRetainedBytes == 0)
    }

    @Test("SQL constructors charge child collections, depth, and retained literal bytes")
    func sqlConstructorStructuralBoundaries() throws {
        let expression: Expression = .array([.row([.string("abcd")])])
        try QueryStructuralValidator.validate(expression)
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .nestingDepth, actual: 3, maximum: 2)) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumNestingDepth: 2))
        }
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .collectionElements, actual: 2, maximum: 1)) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumCollectionElements: 1))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(.array([.literal(.queryValue(.primitive(.string("abcd")), type: .sql(.text)))]),
                limits: QueryStructuralLimits(maximumRetainedBytes: 3))
        }
        let query = SelectQuery(projection: .items([ProjectionItem(.row([
            .col("visible"), .array([.col("nested")])
        ]))]), source: .values([], columnNames: nil))
        #expect(query.referencedColumns == [ColumnRef("visible"), ColumnRef("nested")])
        #expect(Expression.row([.int(1), .null]) != Expression.array([.int(1), .null]))
        #expect(Set([Expression.row([.int(1)]), .row([.int(1)]), .array([.int(1)])]).count == 2)
    }

    @Test("Temporal precision is bounded at semantic admission and never collapsed into nil")
    func temporalPrecisionSemanticAdmission() throws {
        for precision in 0...6 {
            let type = DataType.timestamp(withTimeZone: true, precision: precision)
            try QueryStructuralValidator.validate(.cast(.null, targetType: type))
            #expect(QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
            #expect(type != .timestamp(withTimeZone: true))
        }
        for precision in [-1, 7, Int.max] {
            let type = DataType.time(withTimeZone: false, precision: precision)
            #expect(!QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
            #expect(throws: QueryStructuralValidationError.invalidQueryValue(.incompatibleType)) {
                try QueryStructuralValidator.validate(.cast(.null, targetType: type))
            }
        }
    }

    @Test("Fusion stages, inputs, and schema fields consume structural limits")
    func fusionCollectionsConsumeStructuralLimits() {
        let query = SelectQuery(
            projection: .all,
            source: .table(TableRef("documents")),
            accessPath: .fusion(
                FusionSource(
                    stages: [
                        FusionStageSource(inputs: [
                            FusionInput(
                                operation: .index(
                                    FusionIndexSource(
                                        selection: .matching(
                                            type: .vector,
                                            fields: [
                                                FieldIdentity(name: "embedding", number: 2),
                                            ],
                                            fieldMatch: .exact
                                        ),
                                        referencedFields: [
                                            FieldIdentity(
                                                name: "embedding",
                                                number: 2
                                            ),
                                        ]
                                    )
                                ),
                                scoring: .position
                            ),
                            FusionInput(
                                operation: .filter(
                                    .equal(.col("active"), .literal(.bool(true)))
                                )
                            ),
                        ]),
                    ]
                )
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 5,
                maximum: 4
            )
        ) {
            try QueryStructuralValidator.validate(
                query,
                limits: QueryStructuralLimits(maximumCollectionElements: 4)
            )
        }
    }

    @Test("SQL INSERT accepts the exact collection boundary")
    func sqlInsertCollectionBoundary() throws {
        let statement = QueryStatement.insert(
            InsertQuery(
                target: TableRef("events"),
                columns: ["id", "title"],
                source: .values([[
                    .literal(.int(1)),
                ]])
            )
        )

        try QueryStructuralValidator.validate(
            statement,
            limits: QueryStructuralLimits(maximumCollectionElements: 4)
        )
    }

    @Test("SQL INSERT rejects one collection element beyond the boundary")
    func sqlInsertCollectionOverflow() {
        let statement = QueryStatement.insert(
            InsertQuery(
                target: TableRef("events"),
                columns: ["id", "title"],
                source: .values([[
                    .literal(.int(1)),
                ]])
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 4,
                maximum: 3
            )
        ) {
            try QueryStructuralValidator.validate(
                statement,
                limits: QueryStructuralLimits(maximumCollectionElements: 3)
            )
        }
    }

    @Test("Table partition values cannot bypass collection limits")
    func tablePartitionValueCollectionOverflow() throws {
        let target = TableRef(
            "events",
            partitions: try FieldObject([
                (
                    key: "tenant",
                    value: .array([.int64(1), .int64(2), .int64(3)])
                ),
            ])
        )
        let statement = QueryStatement.insert(
            InsertQuery(target: target, source: .defaultValues)
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 4,
                maximum: 3
            )
        ) {
            try QueryStructuralValidator.validate(
                statement,
                limits: QueryStructuralLimits(maximumCollectionElements: 3)
            )
        }
    }

    @Test("SQL expression depth is bounded without recursive validation")
    func sqlExpressionDepthOverflow() {
        var expression = Expression.column(ColumnRef("value"))
        for _ in 0..<4 {
            expression = .not(expression)
        }
        let statement = QueryStatement.update(
            UpdateQuery(
                target: TableRef("events"),
                assignments: [Assignment(column: "value", value: expression)]
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .nestingDepth,
                actual: 5,
                maximum: 4
            )
        ) {
            try QueryStructuralValidator.validate(
                statement,
                limits: QueryStructuralLimits(maximumNestingDepth: 4)
            )
        }
    }

    @Test("Property graph definitions share the global collection ledger")
    func propertyGraphCollectionOverflow() {
        let definition = VertexTableDefinition(
            tableName: "people",
            keyColumns: ["tenant", "id"],
            labelExpression: .or([.single("Person"), .column("kind")]),
            propertiesSpec: .columns(["name", "email"])
        )
        let statement = QueryStatement.createGraph(
            CreateGraphStatement(
                graphName: "social",
                vertexTables: [definition],
                edgeTables: []
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 7,
                maximum: 6
            )
        ) {
            try QueryStructuralValidator.validate(
                statement,
                limits: QueryStructuralLimits(maximumCollectionElements: 6)
            )
        }
    }

    @Test("SPARQL dataset graphs share the global collection ledger")
    func sparqlDatasetCollectionOverflow() {
        let query = SelectQuery(
            projection: .all,
            source: .graphPattern(.basic([])),
            dataset: .explicit(
                defaultGraphs: ["urn:default:1", "urn:default:2"],
                namedGraphs: ["urn:named:1"]
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 3,
                maximum: 2
            )
        ) {
            try QueryStructuralValidator.validate(
                query,
                limits: QueryStructuralLimits(maximumCollectionElements: 2)
            )
        }
    }

    @Test("VALUES cell limits apply to canonical QueryIR")
    func valuesCellOverflow() {
        let query = SelectQuery(
            projection: .all,
            source: .values(
                [[.int(1), .int(2)]],
                columnNames: ["first", "second"]
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .valuesCells,
                actual: 2,
                maximum: 1
            )
        ) {
            try QueryStructuralValidator.validate(
                query,
                limits: QueryStructuralLimits(maximumValuesCells: 1)
            )
        }
    }

    @Test("SPARQL update operation arrays are bounded")
    func sparqlUpdateOperationCollectionOverflow() {
        let request = SPARQLUpdateRequest(
            firstOperation: .load(LoadQuery(source: "urn:source:1")),
            additionalOperations: [
                .load(LoadQuery(source: "urn:source:2")),
                .load(LoadQuery(source: "urn:source:3")),
            ]
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 2,
                maximum: 1
            )
        ) {
            try QueryStructuralValidator.validate(
                request,
                limits: QueryStructuralLimits(maximumCollectionElements: 1)
            )
        }
    }

    @Test("Total node accounting includes SQL mutation payloads")
    func sqlMutationTotalNodeBoundary() throws {
        let statement = QueryStatement.insert(
            InsertQuery(target: TableRef("events"), source: .defaultValues)
        )

        try QueryStructuralValidator.validate(
            statement,
            limits: QueryStructuralLimits(maximumTotalNodes: 2)
        )
        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .totalNodes,
                actual: 2,
                maximum: 1
            )
        ) {
            try QueryStructuralValidator.validate(
                statement,
                limits: QueryStructuralLimits(maximumTotalNodes: 1)
            )
        }
    }

    @Test("Parameter values are bounded before recursive binding")
    func parameterValueDepthOverflow() {
        var value = FieldValue.object(FieldObject())
        for _ in 0..<4 {
            value = .array([value])
        }
        let parameters = [
            QueryParameter(position: 1, name: "value", value: .primitive(value)),
        ]

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .nestingDepth,
                actual: 4,
                maximum: 3
            )
        ) {
            try QueryStructuralValidator.validate(
                parameters: parameters,
                limits: QueryStructuralLimits(maximumNestingDepth: 3)
            )
        }
    }

    @Test("Standalone expressions use the canonical collection ledger")
    func standaloneExpressionCollectionOverflow() {
        let expression = Expression.function(
            FunctionCall(
                name: "urn:example:function",
                arguments: [
                    .literal(.int(1)),
                    .literal(.int(2)),
                    .literal(.int(3)),
                ]
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 3,
                maximum: 2
            )
        ) {
            try QueryStructuralValidator.validate(
                expression,
                limits: QueryStructuralLimits(
                    maximumCollectionElements: 2
                )
            )
        }
    }

    @Test("Standalone aggregates use the canonical nesting ledger")
    func standaloneAggregateDepthOverflow() {
        let aggregate = AggregateFunction.sum(
            .not(.not(.literal(.int(1)))),
            distinct: false
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .nestingDepth,
                actual: 3,
                maximum: 2
            )
        ) {
            try QueryStructuralValidator.validate(
                aggregate,
                limits: QueryStructuralLimits(
                    maximumNestingDepth: 2
                )
            )
        }
    }
}
