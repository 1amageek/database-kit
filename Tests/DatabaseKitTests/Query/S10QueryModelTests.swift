import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Recursive CTE and table-function declarations")
struct S10QueryModelTests {
    private func query(_ value: Expression = .int(1)) -> SelectQuery {
        let definition = NamedSubquery(name: "walk", columns: ["key"],
            query: SelectQuery(projection: [ProjectionItem(value)], source: .values([])),
            materialized: .notMaterialized,
            search: CTESearchClause(order: .breadthFirst, columns: ["key"], sequenceColumn: "sequence"),
            cycle: CTECycleClause(columns: ["key"], markColumn: "cycle", pathColumn: "path",
                markValue: .string("yes"), defaultValue: .string("no")))
        return SelectQuery(projection: [.wildcard()], source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "unnest", arguments: [value], schema: "pg_catalog",
                finalArrayIsVariadic: true), withOrdinality: true)),
            subqueries: [definition], withRecursive: true)
    }

    @Test("Binding visits function arguments and CTE bodies while retaining all metadata")
    func parameterBinding() throws {
        let statement = QueryStatement.select(query(.parameter(.position(1))))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        try binder.validate(statement)
        #expect(try binder.bind(statement) == .select(query(.int(7))))
        #expect(throws: QueryParameterBindingError.missingPosition(1)) {
            try QueryParameterBinder(parameters: []).validate(statement)
        }
        let argumentOnly = QueryStatement.select(SelectQuery(projection: [.wildcard()], source: .tableFunction(
            TableFunctionSource(function: FunctionCall(name: "unnest", arguments: [.parameter(.name("input"))])))))
        #expect(throws: QueryParameterBindingError.missingName("input")) {
            try QueryParameterBinder(parameters: []).validate(argumentOnly)
        }
    }

    @Test("References reach nested table-function arguments and CTE bodies")
    func references() {
        let value = query(.add(.col("key"), .variable(Variable("argument"))))
        #expect(value.referencedColumns == [ColumnRef("key")])
        #expect(value.referencedVariables == ["argument"])
        #expect(!value.source.usesSPARQLSemantics)
    }

    @Test("Identity distinguishes recursive visibility, generated metadata and ordinality")
    func identity() {
        let value = query()
        #expect(value == query())
        #expect(value.hashValue == query().hashValue)
        #expect(value != value.replacing(withRecursive: false))
        guard let definition = value.subqueries?.first else { Issue.record("Missing CTE"); return }
        let alternatives = [
            NamedSubquery(name: definition.name, columns: definition.columns, query: definition.query,
                materialized: definition.materialized, search: nil, cycle: definition.cycle),
            NamedSubquery(name: definition.name, columns: definition.columns, query: definition.query,
                materialized: definition.materialized,
                search: CTESearchClause(order: .depthFirst, columns: ["key"], sequenceColumn: "sequence"), cycle: definition.cycle),
            NamedSubquery(name: definition.name, columns: definition.columns, query: definition.query,
                materialized: definition.materialized, search: definition.search,
                cycle: CTECycleClause(columns: ["key"], markColumn: "cycle", pathColumn: "other",
                    markValue: .string("yes"), defaultValue: .string("no"))),
            NamedSubquery(name: definition.name, columns: definition.columns, query: definition.query,
                materialized: definition.materialized, search: definition.search,
                cycle: CTECycleClause(columns: ["key"], markColumn: "cycle", pathColumn: "path",
                    markValue: .string("yes"), defaultValue: .null))]
        for alternative in alternatives { #expect(value != value.replacing(subqueries: [alternative])) }
        let function = FunctionCall(name: "unnest", arguments: [.int(1)], schema: "pg_catalog", finalArrayIsVariadic: true)
        #expect(value != value.replacing(source: .tableFunction(TableFunctionSource(function: function))))
        #expect(value != value.replacing(source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "unnest", arguments: [.int(2)]), withOrdinality: true))))
    }

    @Test("Every immutable SELECT replacement retains recursive visibility and CTE metadata")
    func preservingCopies() {
        let value = query()
        let copies = [value.replacing(projection: []), value.replacing(source: .values([])),
            value.replacing(accessPath: nil), value.replacing(filter: .bool(true)), value.replacing(groupBy: []),
            value.replacing(having: nil), value.replacing(windows: []), value.replacing(orderBy: []),
            value.replacing(quantifier: .distinct), value.replacing(pagination: QueryPagination(limit: .all)),
            value.replacing(reduced: true), value.replacing(dataset: .implicit)]
        for copy in copies {
            #expect(copy.withRecursive)
            #expect(copy.subqueries == value.subqueries)
        }
        #expect(value.replacing(subqueries: []).withRecursive)
        #expect(value.replacing(withRecursive: false).subqueries == value.subqueries)
    }

    @Test("Generated metadata uses exact shared node, collection, depth and byte limits")
    func exactMetadataLimits() throws {
        let cte = NamedSubquery(name: "q", query: SelectQuery(projection: [.wildcard()], source: .values([])),
            search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "s"),
            cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p",
                markValue: .string("xx"), defaultValue: .string("y")))
        let value = SelectQuery(projection: [.wildcard()], source: .values([]), subqueries: [cte], withRecursive: true)
        try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumNestingDepth: 3,
            maximumRetainedBytes: 8, maximumTotalNodes: 11, maximumCollectionElements: 5))
        let rejected: [(QueryStructuralLimits, QueryStructuralValidationError.Resource, UInt64, UInt64)] = [
            (QueryStructuralLimits(maximumNestingDepth: 2), .nestingDepth, 3, 2),
            (QueryStructuralLimits(maximumRetainedBytes: 7), .retainedBytes, 8, 7),
            (QueryStructuralLimits(maximumTotalNodes: 10), .totalNodes, 11, 10),
            (QueryStructuralLimits(maximumCollectionElements: 4), .collectionElements, 5, 4)]
        for (limits, resource, actual, maximum) in rejected {
            #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: resource, actual: actual, maximum: maximum)) {
                try QueryStructuralValidator.validate(value, limits: limits)
            }
        }
        let function = SelectQuery(projection: [.wildcard()], source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "f", arguments: [.col("k")], schema: "s"))))
        try QueryStructuralValidator.validate(function, limits: QueryStructuralLimits(maximumNestingDepth: 2,
            maximumRetainedBytes: 2, maximumTotalNodes: 4, maximumCollectionElements: 2))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .totalNodes, actual: 4, maximum: 3)) {
            try QueryStructuralValidator.validate(function, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        }
    }

    @Test("CYCLE binary constants charge the complete retained owner before publication")
    func binaryConstantBudget() throws {
        let bytes = ByteString([1, 2, 3, 4])
        let slice = bytes[1..<2]
        let cte = NamedSubquery(name: "q", query: SelectQuery(projection: [], source: .values([])),
            cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p",
                markValue: .binary(slice), defaultValue: .null))
        let value = SelectQuery(projection: [], source: .values([]), subqueries: [cte], withRecursive: true)
        let required = UInt64(bytes.retainedByteCount!) + 3
        try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumRetainedBytes: required))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .retainedBytes, actual: required, maximum: required - 1)) {
            try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumRetainedBytes: required - 1))
        }
        #expect(slice.count == 1)
    }

    @Test("Invalid intrinsic keys, generated names, constants and function layouts fail typed")
    func invalidLayouts() throws {
        let body = SelectQuery(projection: [], source: .values([]))
        let invalidSearch = [CTESearchClause(order: .depthFirst, columns: [], sequenceColumn: "s"),
            CTESearchClause(order: .depthFirst, columns: ["k", "k"], sequenceColumn: "s"),
            CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "k"),
            CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "")]
        for search in invalidSearch {
            let value = SelectQuery(projection: [], source: .values([]), subqueries: [NamedSubquery(name: "q", query: body, search: search)])
            #expect(throws: QueryStructuralValidationError.invalidCTESearchClause) { try QueryStructuralValidator.validate(value) }
        }
        let invalidCycles = [CTECycleClause(columns: [], markColumn: "m", pathColumn: "p"),
            CTECycleClause(columns: ["k", "k"], markColumn: "m", pathColumn: "p"),
            CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "m"),
            CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .bool(true)),
            CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .array([]), defaultValue: .null),
            CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .iri("iri"), defaultValue: .null)]
        for cycle in invalidCycles {
            let value = SelectQuery(projection: [], source: .values([]), subqueries: [NamedSubquery(name: "q", query: body, cycle: cycle)])
            #expect(throws: QueryStructuralValidationError.invalidCTECycleClause) { try QueryStructuralValidator.validate(value) }
        }
        let collision = NamedSubquery(name: "q", columns: ["s"], query: body,
            search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "s"))
        #expect(throws: QueryStructuralValidationError.invalidCTESearchClause) {
            try QueryStructuralValidator.validate(SelectQuery(projection: [], source: .values([]), subqueries: [collision]))
        }
        for function in [FunctionCall(name: "", arguments: []), FunctionCall(name: "f", arguments: [], schema: ""),
            FunctionCall(name: "f", arguments: [], distinct: true)] {
            #expect(throws: QueryStructuralValidationError.invalidTableFunctionSource) {
                try QueryStructuralValidator.validate(SelectQuery(projection: [], source: .tableFunction(TableFunctionSource(function: function))))
            }
        }
        #expect(throws: QueryStructuralValidationError.emptyVariadicFunctionArguments) {
            try QueryStructuralValidator.validate(SelectQuery(projection: [], source: .tableFunction(TableFunctionSource(
                function: FunctionCall(name: "f", arguments: [], finalArrayIsVariadic: true)))))
        }
    }

    @Test("Deep function arguments traverse iteratively without changing default limits")
    func deepTraversal() throws {
        var argument = Expression.add(.col("key"), .parameter(.position(1)))
        var expected = Expression.add(.col("key"), .int(7))
        for _ in 0..<256 {
            argument = .function(FunctionCall(name: "identity", arguments: [argument]))
            expected = .function(FunctionCall(name: "identity", arguments: [expected]))
        }
        let value = SelectQuery(projection: [], source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "f", arguments: [argument]), withOrdinality: true)))
        let result = value.replacing(source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "f", arguments: [expected]), withOrdinality: true)))
        #expect(value.referencedColumns == [ColumnRef("key")])
        #expect(value == value)
        #expect(value.hashValue == value.hashValue)
        #expect(throws: QueryStructuralValidationError.self) { try QueryStructuralValidator.validate(value) }
        let limits = QueryStructuralLimits(maximumNestingDepth: 512)
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))], structuralLimits: limits)
        #expect(try binder.bind(.select(value)) == .select(result))
        try QueryStructuralValidator.validate(result, limits: limits)
    }

    @Test("SPARQL rejects recursive visibility, generated clauses and table functions explicitly")
    func sparqlBoundary() throws {
        let graph = SelectQuery(projection: [.wildcard()], source: .graphPattern(.basic([])))
        let search = NamedSubquery(name: "q", query: graph,
            search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "s"))
        let cycle = NamedSubquery(name: "q", query: graph,
            cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p"))
        for value in [graph.replacing(withRecursive: true), graph.replacing(subqueries: [search]),
            graph.replacing(subqueries: [cycle]), graph.replacing(source: .tableFunction(TableFunctionSource(
                function: FunctionCall(name: "f", arguments: []))))] {
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(value) }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try value.toSPARQL() }
        }
        try SPARQLSemanticValidator.validate(graph)
    }
}
