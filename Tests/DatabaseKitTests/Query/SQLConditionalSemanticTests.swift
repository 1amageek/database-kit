import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL conditional semantic model")
struct SQLConditionalSemanticTests {
    @Test("Conditional identities include operands, flags, and quantified sources")
    func identities() {
        let pair = CaseWhenPair(condition: .int(1), result: .int(2))
        let searched = Expression.caseWhen(cases: [pair], elseResult: .null)
        let simple = Expression.caseWhen(operand: .int(1), cases: [pair], elseResult: .null)
        let expressions: [Expression] = [searched, simple, .greatest([.int(1)]), .least([.int(1)]),
            .truthTest(.null, value: .true, negated: false), .truthTest(.null, value: .false, negated: false),
            .truthTest(.null, value: .unknown, negated: false), .truthTest(.null, value: .unknown, negated: true),
            .isDistinctFrom(.null, .int(1), negated: false), .isDistinctFrom(.null, .int(1), negated: true)]
        #expect(Set(expressions).count == expressions.count)
        let comparisons: [ComparisonOperator] = [.equal, .notEqual, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual]
        var quantified: Set<Expression> = []
        for comparison in comparisons {
            for quantifier: ComparisonQuantifier in [.any, .all] {
                for source: QuantifiedComparisonSource in [.array(.null), .subquery(query(.null))] {
                    let value = Expression.quantifiedComparison(.int(1), comparison: comparison, quantifier: quantifier, source: source)
                    #expect(value == value)
                    quantified.insert(value)
                }
            }
        }
        #expect(quantified.count == 24)

        // Every direct-child form must retain exact identity through the same
        // 48-edge constructor witness that exposed recursive equality frames.
        func forms(_ child: Expression) -> [Expression] {
            [.array([child]), .row([child]), .add(child, .int(3)), .subtract(child, .int(3)),
             .multiply(child, .int(3)), .divide(child, .int(3)), .modulo(child, .int(3)), .negate(child),
             .equal(child, .int(3)), .notEqual(child, .int(3)), .lessThan(child, .int(3)),
             .lessThanOrEqual(child, .int(3)), .greaterThan(child, .int(3)), .greaterThanOrEqual(child, .int(3)),
             .and(child, .bool(true)), .or(child, .bool(false)), .not(child), .isNull(child), .isNotNull(child),
             .patternMatch(subject: child, pattern: .string("exact"), escape: nil, kind: .like), .concatenate(child, .string("exact")), .regex(child, pattern: "exact", flags: "i"),
             .between(child, low: .int(0), high: .int(3)), .inList(child, values: [.int(3)]),
             .notInList(.int(3), values: [child]), .inSubquery(child, subquery: query(.int(3))),
             .function(FunctionCall(name: "Exact.F", arguments: [child], distinct: true, schema: "Exact.S")),
             .caseWhen(operand: child, cases: [CaseWhenPair(condition: .int(3), result: .null)], elseResult: nil),
             .caseWhen(cases: [CaseWhenPair(condition: .bool(true), result: child)], elseResult: .null),
             .caseWhen(cases: [], elseResult: child), .coalesce([child]), .nullIf(child, .null),
             .greatest([child]), .least([child]), .truthTest(child, value: .unknown, negated: false),
             .isDistinctFrom(child, .null, negated: true),
             .quantifiedComparison(child, comparison: .equal, quantifier: .any, source: .array(.null)),
             .quantifiedComparison(.null, comparison: .equal, quantifier: .all, source: .array(child)),
             .cast(child, targetType: .custom("Exact.T", schema: "Exact.S")),
             .triple(subject: child, predicate: .int(2), object: .int(3)), .isTriple(child),
             .subject(child), .predicate(child), .object(child),
             .subquery(query(child)), .exists(query(child)),
             .aggregate(.count(child, distinct: true)), .aggregate(.sum(child, distinct: true)),
             .aggregate(.avg(child, distinct: false)), .aggregate(.min(child)), .aggregate(.max(child)),
             .aggregate(.groupConcat(child, separator: ",", distinct: true)), .aggregate(.sample(child)),
             .aggregate(.arrayAgg(child, orderBy: [SortKey(.int(3), direction: .descending, nulls: .last)], distinct: true)),
             .aggregate(.arrayAgg(.int(3), orderBy: [SortKey(child)], distinct: false))]
        }
        func nested(_ leaf: Expression) -> Expression {
            var value = leaf
            for _ in 0..<24 { value = .array([.row([value])]) }
            return value
        }
        let first = forms(nested(.int(1)))
        let equal = forms(nested(.int(1)))
        let unequal = forms(nested(.int(2)))
        #expect(first.count == equal.count && equal.count == unequal.count)
        for index in first.indices {
            #expect(first[index] == equal[index])
            #expect(first[index].hashValue == equal[index].hashValue)
            #expect(first[index] != unequal[index])
        }
        #expect(Expression.row([.int(1), .int(2)]) != .row([.int(2), .int(1)]))
        #expect(Expression.aggregate(.count(nil, distinct: false)) != .aggregate(.count(.null, distinct: false)))
        #expect(Expression.aggregate(.arrayAgg(.null, orderBy: nil, distinct: false)) != .aggregate(.arrayAgg(.null, orderBy: [], distinct: false)))
        #expect(Expression.aggregate(.arrayAgg(.null, orderBy: [SortKey(.int(1), direction: .ascending)], distinct: false))
            != .aggregate(.arrayAgg(.null, orderBy: [SortKey(.int(1), direction: .descending)], distinct: false)))
    }

    @Test("Binding reaches each new child and preserves declared NULL metadata")
    func parameterChildren() throws {
        let parameter = Expression.parameter(.position(1))
        let type = QueryColumnType.sql(.integer)
        let bound = Expression.literal(.queryValue(.primitive(.null), type: type))
        func expression(_ child: Expression) -> Expression {
            .row([
                .caseWhen(operand: child, cases: [CaseWhenPair(condition: child, result: child)], elseResult: child),
                .greatest([child]), .least([child]), .truthTest(child, value: .unknown, negated: true),
                .isDistinctFrom(child, child, negated: true),
                .quantifiedComparison(child, comparison: .lessThan, quantifier: .any, source: .array(child)),
                .quantifiedComparison(child, comparison: .greaterThanOrEqual, quantifier: .all, source: .subquery(query(child))),
            ])
        }
        let statement = QueryStatement.select(query(expression(parameter)))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.null), type: type)])
        try binder.validate(statement)
        #expect(try binder.bind(statement) == .select(query(expression(bound))))
        #expect(throws: QueryParameterBindingError.missingPosition(1)) {
            try QueryParameterBinder(parameters: []).validate(statement)
        }
    }

    @Test("A simple CASE operand contributes exactly one structural node")
    func structuralBoundaries() throws {
        let parameter = Expression.parameter(.position(1))
        let expression = Expression.caseWhen(operand: parameter,
            cases: [CaseWhenPair(condition: parameter, result: parameter)], elseResult: parameter)
        try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 5))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .totalNodes, actual: 5, maximum: 4)) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 4))
        }
        for expression: Expression in [.greatest([parameter, parameter]), .least([parameter, parameter])] {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumCollectionElements: 2))
            #expect(throws: QueryStructuralValidationError.self) {
                try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumCollectionElements: 1))
            }
        }
        let quantified = Expression.quantifiedComparison(parameter, comparison: .equal, quantifier: .all, source: .array(parameter))
        try QueryStructuralValidator.validate(quantified, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(quantified, limits: QueryStructuralLimits(maximumTotalNodes: 2))
        }
    }

    @Test("Reference helpers traverse conditional operands and quantified scopes")
    func referencedChildren() {
        func expression(_ reference: (String) -> Expression, subquery: (Expression) -> SelectQuery) -> Expression {
            .row([
                .caseWhen(operand: reference("operand"), cases: [CaseWhenPair(condition: reference("match"), result: reference("result"))], elseResult: reference("fallback")),
                .greatest([reference("greatest")]), .least([reference("least")]),
                .truthTest(reference("truth"), value: .true, negated: false),
                .isDistinctFrom(reference("left"), reference("right"), negated: false),
                .quantifiedComparison(reference("lhs"), comparison: .equal, quantifier: .any, source: .array(reference("array"))),
                .quantifiedComparison(reference("outer"), comparison: .equal, quantifier: .all, source: .subquery(subquery(reference("inner")))),
            ])
        }
        let names: Set<String> = ["operand", "match", "result", "fallback", "greatest", "least", "truth", "left", "right", "lhs", "array", "outer", "inner"]
        #expect(query(expression({ .col($0) }, subquery: query)).referencedColumns == Set(names.map { ColumnRef($0) }))
        func filtered(_ value: Expression) -> SelectQuery {
            SelectQuery(projection: [.wildcard()], source: .values([]), filter: value)
        }
        #expect(filtered(expression({ .variable(Variable($0)) }, subquery: filtered)).referencedVariables == names)
    }

    @Test("SQL conditional additions are rejected by RDF policy gates")
    func sparqlPolicy() throws {
        let expressions: [Expression] = [
            .caseWhen(operand: .int(1), cases: [CaseWhenPair(condition: .int(1), result: .int(2))], elseResult: nil),
            .greatest([.int(1)]), .least([.int(1)]), .truthTest(.null, value: .unknown, negated: false),
            .isDistinctFrom(.null, .null, negated: false),
            .quantifiedComparison(.int(1), comparison: .equal, quantifier: .any, source: .array(.null)),
            .quantifiedComparison(.int(1), comparison: .equal, quantifier: .all, source: .subquery(query(.null))),
        ]
        for expression in expressions {
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(query(expression)) }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try expression.toSPARQL() }
        }
        let searched = Expression.caseWhen(cases: [CaseWhenPair(condition: .literal(.bool(true)), result: .int(1))], elseResult: .int(0))
        try SPARQLSemanticValidator.validate(query(searched).replacing(source: .graphPattern(.basic([]))))
        #expect(try searched.toSPARQL().contains("IF("))
    }

    private func query(_ expression: Expression) -> SelectQuery {
        SelectQuery(projection: [ProjectionItem(expression, alias: "value")], source: .values([]))
    }
}
