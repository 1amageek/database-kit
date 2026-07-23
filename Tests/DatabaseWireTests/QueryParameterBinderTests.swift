import DatabaseValue
import QueryIR
import Testing

@Suite("Query parameter binding")
struct QueryParameterBinderTests {
    @Test("named and positional parameters bind throughout a statement")
    func namedAndPositionalParametersBind() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.parameter(.name("projection")), alias: "value"),
                ]),
                source: .table(TableRef("Event")),
                filter: .and(
                    .equal(.col("id"), .parameter(.position(1))),
                    .equal(.col("title"), .parameter(.name("title")))
                ),
                orderBy: [SortKey(.parameter(.position(2)))]
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(number: 1, name: "id", value: .string("event-1")),
            DatabaseObjectField(number: 2, name: "title", value: .string("Festival")),
            DatabaseObjectField(number: 3, name: "projection", value: .int64(42)),
        ])

        let bound = try binder.bind(statement)
        guard case .select(let query) = bound else {
            Issue.record("Expected a SELECT statement")
            return
        }

        #expect(query.projection == .items([
            ProjectionItem(.literal(.int(42)), alias: "value"),
        ]))
        #expect(query.filter == .and(
            .equal(.col("id"), .literal(.string("event-1"))),
            .equal(.col("title"), .literal(.string("Festival")))
        ))
        #expect(query.orderBy == [SortKey(.literal(.string("Festival")))])
    }

    @Test("missing and duplicate bindings fail deterministically")
    func invalidBindingsFail() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(.parameter(.position(2)))]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(number: 1, name: "id", value: .string("event-1")),
        ])

        #expect(throws: QueryParameterBindingError.missingPosition(2)) {
            _ = try binder.bind(statement)
        }
        #expect(throws: QueryParameterBindingError.duplicatePosition(1)) {
            _ = try QueryParameterBinder(parameters: [
                DatabaseObjectField(number: 1, name: "first", value: .null),
                DatabaseObjectField(number: 1, name: "second", value: .null),
            ])
        }
        #expect(throws: QueryParameterBindingError.duplicateName("same")) {
            _ = try QueryParameterBinder(parameters: [
                DatabaseObjectField(number: 1, name: "same", value: .null),
                DatabaseObjectField(number: 2, name: "same", value: .null),
            ])
        }
    }

    @Test("unsigned and decimal parameters retain their canonical types")
    func exactNumericValuesRetainTypes() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.parameter(.name("count"))),
                    ProjectionItem(.parameter(.name("amount"))),
                ]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(
                number: 1,
                name: "count",
                value: .uint64(UInt64.max)
            ),
            DatabaseObjectField(
                number: 2,
                name: "amount",
                value: .decimal(coefficient: 1234, scale: 2)
            ),
        ])

        guard case .select(let query) = try binder.bind(statement) else {
            Issue.record("Expected a SELECT statement")
            return
        }
        #expect(query.projection == .items([
            ProjectionItem(.literal(.uint(UInt64.max))),
            ProjectionItem(.literal(.decimal(coefficient: 1234, scale: 2))),
        ]))
    }

    @Test("values without a query literal representation are rejected")
    func unsupportedValuesAreRejected() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(.parameter(.name("reference")))]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(
                number: 1,
                name: "reference",
                value: .reference(
                    PersistableIdentity(
                        entity: "Event",
                        id: .string("event-1")
                    )
                )
            ),
        ])

        #expect(throws: QueryParameterBindingError.unsupportedValue(.name("reference"))) {
            _ = try binder.bind(statement)
        }
    }

    @Test("Repeated parameter expansion is admitted before materialization")
    func repeatedParameterExpansionIsBounded() throws {
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([
                    ProjectionItem(.parameter(.position(1)), alias: "first"),
                    ProjectionItem(.parameter(.position(1)), alias: "second"),
                ]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(
            parameters: [
                DatabaseObjectField(
                    number: 1,
                    name: "values",
                    value: .array([.int64(1), .int64(2), .int64(3)])
                ),
            ],
            structuralLimits: QueryStructuralLimits(
                maximumCollectionElements: 7
            )
        )

        #expect(
            throws: QueryStructuralValidationError.resourceLimitExceeded(
                resource: .collectionElements,
                actual: 8,
                maximum: 7
            )
        ) {
            _ = try binder.bind(statement)
        }
    }

    @Test("Deep admitted expressions and parameter arrays bind without process-stack recursion")
    func deepExpressionAndParameterArrayBindIteratively() throws {
        let nestingCount = 256
        var expression = Expression.parameter(.position(1))
        var parameterValue = FieldValue.int64(7)
        for _ in 0..<nestingCount {
            expression = .not(expression)
            parameterValue = .array([parameterValue])
        }

        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(expression)]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(
            parameters: [
                DatabaseObjectField(
                    number: 1,
                    name: "",
                    value: parameterValue
                ),
            ],
            structuralLimits: QueryStructuralLimits(
                maximumNestingDepth: 1_024,
                maximumTotalNodes: 4_096,
                maximumCollectionElements: 4_096
            )
        )

        guard case .select(let query) = try binder.bind(statement),
              case .items(let items) = query.projection,
              let projectionItem = items.first else {
            Issue.record("Expected a bound SELECT projection")
            return
        }

        var boundExpression = projectionItem.expression
        for _ in 0..<nestingCount {
            guard case .not(let nested) = boundExpression else {
                Issue.record("Expected the admitted expression nesting to be preserved")
                return
            }
            boundExpression = nested
        }
        guard case .literal(var literal) = boundExpression else {
            Issue.record("Expected the parameter to become a literal")
            return
        }
        for _ in 0..<nestingCount {
            guard case .array(let values) = literal, values.count == 1 else {
                Issue.record("Expected the admitted parameter nesting to be preserved")
                return
            }
            literal = values[0]
        }
        #expect(literal == .int(7))
    }

    @Test("Deep admitted graph patterns bind without process-stack recursion")
    func deepGraphPatternBindsIteratively() throws {
        let nestingCount = 256
        var pattern = GraphPattern.filter(
            .basic([]),
            .parameter(.name("enabled"))
        )
        for _ in 0..<nestingCount {
            pattern = .optional(pattern, .basic([]))
        }
        let statement = QueryStatement.ask(AskQuery(pattern: pattern))
        let binder = try QueryParameterBinder(
            parameters: [
                DatabaseObjectField(
                    number: 1,
                    name: "enabled",
                    value: .bool(true)
                ),
            ],
            structuralLimits: QueryStructuralLimits(
                maximumNestingDepth: 1_024,
                maximumTotalNodes: 4_096,
                maximumCollectionElements: 4_096,
                maximumBasicGraphPatterns: 1_024
            )
        )

        guard case .ask(let query) = try binder.bind(statement) else {
            Issue.record("Expected an ASK statement")
            return
        }
        var boundPattern = query.pattern
        for _ in 0..<nestingCount {
            guard case .optional(let nested, .basic([])) = boundPattern else {
                Issue.record("Expected the admitted graph nesting to be preserved")
                return
            }
            boundPattern = nested
        }
        guard case .filter(.basic([]), let expression) = boundPattern else {
            Issue.record("Expected the innermost filter")
            return
        }
        #expect(expression == .literal(.bool(true)))
    }

    @Test("UUID parameters retain their canonical type")
    func uuidParametersRetainType() throws {
        let uuid = DatabaseUUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )
        let statement = QueryStatement.select(
            SelectQuery(
                projection: .items([ProjectionItem(.parameter(.position(1)))]),
                source: .table(TableRef("Event"))
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(number: 1, name: "id", value: .uuid(uuid)),
        ])

        guard case .select(let query) = try binder.bind(statement) else {
            Issue.record("Expected a SELECT statement")
            return
        }
        #expect(query.projection == .items([ProjectionItem(.literal(.uuid(uuid)))]))
    }

    @Test("SPARQL query forms bind solution modifier expressions")
    func sparqlSolutionModifiersBind() throws {
        let statement = QueryStatement.ask(
            AskQuery(
                pattern: .basic([]),
                dataset: .explicit(
                    defaultGraphs: ["urn:default"],
                    namedGraphs: ["urn:named"]
                ),
                modifiers: SPARQLSolutionModifiers(
                    groupBy: [.parameter(.position(1))],
                    having: [.parameter(.name("having"))],
                    orderBy: [SortKey(.parameter(.position(2)))],
                    limit: 4,
                    offset: 3
                )
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(number: 1, name: "group", value: .string("g")),
            DatabaseObjectField(number: 2, name: "having", value: .bool(true)),
        ])

        guard case .ask(let query) = try binder.bind(statement) else {
            Issue.record("Expected an ASK statement")
            return
        }
        #expect(query.dataset == .explicit(
            defaultGraphs: ["urn:default"],
            namedGraphs: ["urn:named"]
        ))
        #expect(query.modifiers == SPARQLSolutionModifiers(
            groupBy: [.literal(.string("g"))],
            having: [.literal(.bool(true))],
            orderBy: [SortKey(.literal(.bool(true)))],
            limit: 4,
            offset: 3
        ))
    }

    @Test("SPARQL Modify binding preserves WITH and USING semantics")
    func sparqlModifyBindingPreservesGraphSelection() throws {
        let statement = QueryStatement.sparqlUpdate(
            SPARQLUpdateRequest(
                firstOperation: .modify(
                    SPARQLModifyOperation(
                        withGraph: "urn:with",
                        action: .delete([]),
                        using: [
                            GraphRef(iri: "urn:using", isNamed: true),
                        ],
                        wherePattern: .filter(
                            .basic([]),
                            .parameter(.name("enabled"))
                        )
                    )
                ),
                additionalOperations: [
                    .load(LoadQuery(source: "urn:source")),
                    .modify(
                        SPARQLModifyOperation(
                            action: .insert([]),
                            wherePattern: .filter(
                                .basic([]),
                                .parameter(.name("enabled"))
                            )
                        )
                    ),
                ]
            )
        )
        let binder = try QueryParameterBinder(parameters: [
            DatabaseObjectField(
                number: 1,
                name: "enabled",
                value: .bool(true)
            ),
        ])

        guard case .sparqlUpdate(let request) = try binder.bind(statement),
              case .modify(let query) = request[0],
              case .load(let load) = request[1],
              case .modify(let additionalQuery) = request[2] else {
            Issue.record("Expected ordered Modify, LOAD, Modify operations")
            return
        }
        #expect(request.count == 3)
        #expect(query.withGraph == "urn:with")
        #expect(query.using == [GraphRef(iri: "urn:using", isNamed: true)])
        #expect(query.wherePattern == .filter(
            .basic([]),
            .literal(.bool(true))
        ))
        #expect(load == LoadQuery(source: "urn:source"))
        #expect(additionalQuery.wherePattern == .filter(
            .basic([]),
            .literal(.bool(true))
        ))
    }
}
