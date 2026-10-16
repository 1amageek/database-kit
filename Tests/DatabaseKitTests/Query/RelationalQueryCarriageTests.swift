import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Relational query carriage")
struct RelationalQueryCarriageTests {
    @Test("Canonical copies preserve ordered projection, query tails and exact names")
    func canonicalCopies() throws {
        let original = SelectQuery(
            projection: [.wildcard(), ProjectionItem(.int(1), alias: "duplicate"), .wildcard(qualifier: "input")],
            source: .aliased(.values([[.int(1)]]), name: "input", columns: ["duplicate"]),
            filter: .bool(true), orderBy: [SortKey(.collate(.col("duplicate"), collation: .c))],
            quantifier: .distinctOn([.col("duplicate")]),
            pagination: QueryPagination(limit: .count(.fixed(2), withTies: true), offset: .expression(.null)),
            subqueries: [NamedSubquery(name: "input", columns: ["duplicate"],
                query: SelectQuery(projection: [ProjectionItem(.int(1))], source: .values([[]])),
                materialized: .notMaterialized)]
        )
        try QueryStructuralValidator.validate(original)
        #expect(original.replacing(filter: nil).filter == nil)
        #expect(original.replacing(orderBy: nil).orderBy == nil)
        #expect(original.replacing(projection: []).pagination == original.pagination)
        #expect(original.replacing(source: .values([])).subqueries == original.subqueries)
        #expect(original.replacing(pagination: QueryPagination()).quantifier == original.quantifier)
        #expect(original != original.replacing(quantifier: .distinct))
        #expect(original != original.replacing(pagination: QueryPagination(limit: .all)))
        let composed = SelectQuery(projection: [], source: .aliased(.values([]), name: "é"))
        let decomposed = SelectQuery(projection: [], source: .aliased(.values([]), name: "e\u{301}"))
        #expect(composed != decomposed)
        #expect(Set([composed, decomposed]).count == 2)
    }

    @Test("Parameters reach VALUES, query operands, expansion, DISTINCT and pagination")
    func parametersReachEveryNewChild() throws {
        func query(_ child: (UInt32) -> Expression) -> SelectQuery {
            let left = SelectQuery(projection: [ProjectionItem(child(1))], source: .values([[child(2)]]))
            let right = SelectQuery(projection: [ProjectionItem(child(3))], source: .values([[]]))
            let set = SelectQuery(projection: [.wildcard()], source: .setOperation(
                operator: .except, quantifier: .all, left: left, right: right))
            return SelectQuery(
                projection: [.wildcard(qualifier: "selected"), ProjectionItem(.row([
                    .field(.fieldExpansion(child(4)), name: "field"),
                    .collate(child(5), collation: .posix), .arraySubquery(left), .wholeRow("selected")
                ]))],
                source: .aliased(.subquery(set), name: "selected", columns: ["value"]),
                orderBy: [SortKey(child(6))], quantifier: .distinctOn([child(7)]),
                pagination: QueryPagination(limit: .count(.expression(child(8)), withTies: true), offset: .expression(child(9)))
            )
        }
        let statement = QueryStatement.select(query { .parameter(.position($0)) })
        let binder = try QueryParameterBinder(parameters: (1...9).map {
            QueryParameter(position: UInt32($0), value: .primitive(.int64(Int64($0))))
        })
        #expect(try binder.bind(statement) == .select(query { .int(Int64($0)) }))
        #expect(throws: QueryParameterBindingError.missingPosition(2)) {
            try QueryParameterBinder(parameters: (1...9).filter { $0 != 2 }.map {
                QueryParameter(position: UInt32($0), value: .primitive(.int64(Int64($0))))
            }).validate(statement)
        }
    }

    @Test("Invalid source, VALUES and set envelope shapes fail intrinsically")
    func intrinsicShapeFailures() {
        let leaf = SelectQuery(projection: [.wildcard()], source: .values([[]]))
        let set = leaf.replacing(source: .setOperation(operator: .union, quantifier: .distinct, left: leaf, right: leaf))
        #expect(throws: QueryStructuralValidationError.emptyDistinctOn) {
            try QueryStructuralValidator.validate(leaf.replacing(quantifier: .distinctOn([])))
        }
        #expect(throws: QueryStructuralValidationError.invalidSetQueryEnvelope) {
            try QueryStructuralValidator.validate(set.replacing(filter: .bool(true)))
        }
        #expect(throws: QueryStructuralValidationError.invalidSetQueryEnvelope) {
            try QueryStructuralValidator.validate(leaf.replacing(source: .aliased(set.source, name: "set")))
        }
        #expect(throws: QueryStructuralValidationError.invalidValuesRowArity(row: 1, expected: 1, actual: 2)) {
            try QueryStructuralValidator.validate(leaf.replacing(source: .values([[.int(1)], [.int(2), .int(3)]])))
        }
        #expect(throws: QueryStructuralValidationError.sourceAliasInTableReference) {
            try QueryStructuralValidator.validate(leaf.replacing(source: .table(TableRef(table: "item", alias: "input"))))
        }
    }

    @Test("Only direct VALUES expansion defers raw arity to binding")
    func valuesExpansionDefersArity() throws {
        let expansion = Expression.fieldExpansion(.row([.int(1), .int(2)]))
        let admittedRows: [[[Expression]]] = [
            [[expansion], [.int(3), .int(4)]],
            [[.int(3), .int(4)], [expansion]],
            [[.int(3)], [.int(4), .int(5)], [expansion]],
            // Equal raw widths can still have unequal expanded widths; binding rejects them.
            [[expansion], [.int(3)]],
        ]
        for rows in admittedRows {
            let query = SelectQuery(projection: [.wildcard()], source: .values(rows))
            try QueryStructuralValidator.validate(query)
            #expect(query.source == .values(rows))
        }
        let nested = Expression.row([expansion])
        #expect(throws: QueryStructuralValidationError.invalidValuesRowArity(row: 1, expected: 1, actual: 2)) {
            try QueryStructuralValidator.validate(SelectQuery(projection: [.wildcard()],
                source: .values([[nested], [.int(3), .int(4)]])))
        }
    }

    @Test("Alias and VALUES grouping obey exact structural resource boundaries")
    func resourceBoundaries() throws {
        let query = SelectQuery(projection: [], source: .aliased(.values([[]]), name: "abc"))
        try QueryStructuralValidator.validate(query, limits: QueryStructuralLimits(
            maximumNestingDepth: 3, maximumRetainedBytes: 3, maximumTotalNodes: 4,
            maximumCollectionElements: 1, maximumValuesRows: 1, maximumValuesCells: 0))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .retainedBytes, actual: 3, maximum: 2)) {
            try QueryStructuralValidator.validate(query, limits: QueryStructuralLimits(maximumRetainedBytes: 2))
        }
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .totalNodes, actual: 4, maximum: 3)) {
            try QueryStructuralValidator.validate(query, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        }
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .nestingDepth, actual: 3, maximum: 2)) {
            try QueryStructuralValidator.validate(query, limits: QueryStructuralLimits(maximumNestingDepth: 2))
        }
    }

    @Test("Mixed query and expression identity and substitution use iterative traversal")
    func mixedDeepIdentityAndBinding() throws {
        func chain(_ leaf: Expression) -> Expression {
            var expression = leaf
            for _ in 0..<128 {
                expression = .arraySubquery(SelectQuery(
                    projection: [ProjectionItem(.fieldExpansion(expression))], source: .values([[]])))
            }
            return expression
        }
        let parameterized = chain(.parameter(.position(1)))
        let expected = chain(.int(7))
        #expect(expected == chain(.int(7)))
        #expect(expected != chain(.int(8)))
        #expect(Set([expected, chain(.int(7)), chain(.int(8))]).count == 2)
        let query = SelectQuery(projection: [ProjectionItem(parameterized)], source: .values([[]]))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))],
            structuralLimits: QueryStructuralLimits(maximumNestingDepth: 2_048))
        #expect(try binder.bind(.select(query)) == .select(query.replacing(projection: [ProjectionItem(expected)])))
    }

    @Test("SPARQL retains unsigned fixed counts and rejects SQL-only query declarations")
    func sparqlIsolationAndUnsignedCounts() throws {
        let query = SelectQuery(projection: [.wildcard()], source: .graphPattern(.basic([])),
            quantifier: .distinct,
            pagination: QueryPagination(limit: .count(.fixed(UInt64.max), withTies: false), offset: .fixed(UInt64.max)))
        try SPARQLSemanticValidator.validate(query)
        #expect(try query.toSPARQL().contains("LIMIT 18446744073709551615"))
        for pagination in [QueryPagination(limit: .all), QueryPagination(offset: .expression(.null)),
                           QueryPagination(limit: .count(.fixed(1), withTies: true))] {
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) {
                try SPARQLSemanticValidator.validate(query.replacing(pagination: pagination))
            }
        }
        #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) {
            try SPARQLSemanticValidator.validate(query.replacing(quantifier: .distinctOn([.int(1)])))
        }
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
            try Expression.fieldExpansion(.wholeRow("row")).toSPARQL()
        }
    }

    @Test("Relational occurrence roles retain independent repeated-row addresses")
    func occurrenceAddresses() throws {
        var arena = QueryOccurrenceArena()
        let root = try arena.append()
        let source = try arena.append(parent: root, field: .source)
        let row0 = try arena.append(parent: source, field: .valuesRow, index: 0)
        let row1 = try arena.append(parent: source, field: .valuesRow, index: 1)
        let first = try arena.append(parent: row0, field: .valuesCell, index: 0)
        let second = try arena.append(parent: row1, field: .valuesCell, index: 0)
        #expect(first != second)
        #expect(arena.child(of: row0, field: .valuesCell, index: 0) == first)
        for role: QueryOccurrenceField in [.distinctOn, .offset, .limit, .setLeft, .setRight] {
            let id = try arena.append(parent: root, field: role)
            #expect(arena.child(of: root, field: role) == id)
        }
        #expect(throws: QueryOccurrenceError.duplicateOccurrence) {
            try arena.append(parent: row0, field: .valuesCell, index: 0)
        }
    }
}
