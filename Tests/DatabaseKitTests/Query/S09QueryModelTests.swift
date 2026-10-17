import DatabaseTypes
import DatabaseKit
import Testing

@Suite("SQL grouping, aggregate and window declarations")
struct S09QueryModelTests {
    private func query(_ value: Expression) -> SelectQuery {
        let call = SQLAggregateCall(function: .percentileCont, arguments: [value], distinct: true,
            orderBy: [SortKey(value, direction: .descending, nulls: .last)], filter: value,
            withinGroup: [SortKey(value)], schema: "pg_catalog")
        let spec = WindowSpecification(inheritedName: "inherited", partitionBy: [value],
            orderBy: [SortKey(value)], frame: WindowFrame(mode: .groups,
                start: .preceding(value), end: .following(value), exclusion: .ties))
        return SelectQuery(projection: [ProjectionItem(.aggregate(.sql(call))),
            ProjectionItem(.grouping([value])),
            ProjectionItem(.window(WindowCall(function: .aggregate(call), reference: .specification(spec)))),
            ProjectionItem(.window(WindowCall(function: .analytic(.lag, arguments: [value, value, value]), reference: .named("named"))))],
            source: .values([[]]), groupBy: [.groupingSets([[], [.rollup([[value], [value, value]])],
                [.cube([[value]])], [.expression(value)]])], having: value,
            windows: [NamedWindow(name: "named", specification: spec)])
    }

    @Test("Parameter validation and binding visit every grouping, modifier and window child")
    func everyChildBinds() throws {
        let statement = QueryStatement.select(query(.parameter(.position(1))))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        try binder.validate(statement)
        #expect(try binder.bind(statement) == .select(query(.int(7))))
        #expect(throws: QueryParameterBindingError.missingPosition(1)) {
            try QueryParameterBinder(parameters: []).validate(statement)
        }
    }

    @Test("Identity retains grouping shape, every SQL modifier and frame metadata")
    func identityPreservesMetadata() {
        let value = query(.col("key"))
        #expect(value == query(.col("key")))
        #expect(value.hashValue == query(.col("key" )).hashValue)
        #expect(value != query(.col("different")))
        #expect(value != value.replacing(groupBy: [.expression(.col("key"))]))
        #expect(value != value.replacing(windows: []))
        let absent = Expression.aggregate(.sql(SQLAggregateCall(function: .sum, arguments: [.int(1)])))
        let present = Expression.aggregate(.sql(SQLAggregateCall(function: .sum, arguments: [.int(1)], withinGroup: [])))
        #expect(absent != present)
        var left = GroupingElement.expression(.col("key"))
        var right = GroupingElement.expression(.col("key"))
        for _ in 0..<512 {
            left = .groupingSets([[left]])
            right = .groupingSets([[right]])
        }
        #expect(left == right)
        #expect(left.hashValue == right.hashValue)
        #expect(SQLAggregateFunction.allCases.count == 38)
        #expect(SQLWindowFunction.allCases.count == 11)
    }

    @Test("References reach nested groups, aggregate modifiers and both frame bounds")
    func referencesReachChildren() {
        let aggregate = SQLAggregateCall(function: .sum, arguments: [.col("argument")],
            orderBy: [SortKey(.col("aggregateOrder"))], filter: .col("aggregateFilter"),
            withinGroup: [SortKey(.col("within"))])
        let spec = WindowSpecification(partitionBy: [.col("partition")], orderBy: [SortKey(.col("windowOrder"))],
            frame: WindowFrame(mode: .rows, start: .preceding(.col("start")), end: .following(.col("end"))))
        let value = SelectQuery(projection: [ProjectionItem(.window(WindowCall(function: .aggregate(aggregate), reference: .specification(spec)))),
            ProjectionItem(.grouping([.col("grouping")]))], source: .values([[]]),
            groupBy: [.groupingSets([[.rollup([[.col("rollup")]])], [.cube([[.col("cube")]])], [.expression(.col("plain"))]])],
            windows: [NamedWindow(name: "named", specification: WindowSpecification(partitionBy: [.col("namedPartition")]))])
        #expect(value.referencedColumns == Set(["argument", "aggregateOrder", "aggregateFilter", "within", "partition",
            "windowOrder", "start", "end", "grouping", "rollup", "cube", "plain", "namedPartition"].map(ColumnRef.init)))
    }

    @Test("Every SELECT preserving copy retains grouping and named windows")
    func preservingCopies() {
        let value = query(.int(1))
        let copies = [value.replacing(projection: [.wildcard()]), value.replacing(source: .values([])),
            value.replacing(accessPath: nil), value.replacing(filter: .bool(true)), value.replacing(having: nil),
            value.replacing(orderBy: []), value.replacing(quantifier: .distinct),
            value.replacing(pagination: QueryPagination(limit: .all)), value.replacing(subqueries: []),
            value.replacing(reduced: true), value.replacing(dataset: .implicit)]
        for copy in copies {
            #expect(copy.groupBy == value.groupBy)
            #expect(copy.windows == value.windows)
        }
        #expect(value.replacing(groupBy: []).windows == value.windows)
        #expect(value.replacing(windows: []).groupBy == value.groupBy)
    }

    @Test("Structural budgets include new children and reject one-past limits")
    func structuralLimits() throws {
        let value = Expression.grouping([.col("a"), .col("b")])
        try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumNestingDepth: 1,
            maximumTotalNodes: 3, maximumCollectionElements: 2))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumTotalNodes: 2))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumCollectionElements: 1))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(query(.col("value")), limits: QueryStructuralLimits(maximumNestingDepth: 3))
        }
        let source = SelectQuery(projection: [.wildcard()], source: .setOperation(operator: .union,
            quantifier: .all, left: query(.int(1)), right: query(.int(2))),
            windows: [NamedWindow(name: "invalid", specification: WindowSpecification())])
        #expect(throws: QueryStructuralValidationError.invalidSetQueryEnvelope) {
            try QueryStructuralValidator.validate(source)
        }
    }

    @Test("SPARQL rejects SQL-only grouping, aggregates and windows explicitly")
    func sparqlLanguageBoundary() throws {
        let sqlOnly: [Expression] = [.grouping([.int(1)]), .aggregate(.sql(SQLAggregateCall(function: .count, arguments: []))),
            .window(WindowCall(function: .analytic(.rowNumber, arguments: []), reference: .specification(WindowSpecification())))]
        for expression in sqlOnly {
            let value = SelectQuery(projection: [ProjectionItem(expression, alias: "value")], source: .graphPattern(.basic([])))
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(value) }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try value.toSPARQL() }
        }
        for value in [SelectQuery(projection: [.wildcard()], source: .graphPattern(.basic([])), groupBy: [.groupingSets([[]])]),
            SelectQuery(projection: [.wildcard()], source: .graphPattern(.basic([])), windows: [NamedWindow(name: "w", specification: WindowSpecification())])] {
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(value) }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try value.toSPARQL() }
        }
        try SPARQLSemanticValidator.validate(SelectQuery(projection: [ProjectionItem(.aggregate(.count(nil, distinct: false)), alias: "count")],
            source: .graphPattern(.basic([]))))
    }
}
