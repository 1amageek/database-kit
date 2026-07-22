import DatabaseValue
import QueryIR
import Testing

@Suite("Query structural validation")
struct QueryStructuralValidatorTests {
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
    func tablePartitionValueCollectionOverflow() {
        let target = TableRef(
            "events",
            partitions: [
                DatabaseObjectField(
                    number: 1,
                    name: "tenant",
                    value: .array([.int64(1), .int64(2), .int64(3)])
                )
            ]
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
        var value = DatabaseValue.object([])
        for _ in 0..<4 {
            value = .array([value])
        }
        let parameters = [
            DatabaseObjectField(number: 1, name: "value", value: value),
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
}
