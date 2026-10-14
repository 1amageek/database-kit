import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Query value integration")
struct QueryValueIntegrationTests {
    private let valueLimits = QueryValueLimits(
        maximumRetainedBytes: 4 * 1024 * 1024,
        maximumTotalNodes: 10_000,
        maximumNestingDepth: 64,
        maximumCollectionElements: 10_000
    )

    private func richValues() throws -> [QueryValue] {
        let json = try QueryJSONValue(bytes: ByteString(Array("{\"x\":1}".utf8)), limits: valueLimits)
        return [
            .numeric(try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 2)),
            .json(json),
            .jsonb(try QueryJSONBValue(json: json, limits: valueLimits)),
            .array(try QueryArrayValue(
                elementType: .bigint,
                dimensions: [try QueryArrayDimension(lowerBound: -2, length: 2)],
                elements: [.primitive(.int64(7)), .primitive(.null)],
                limits: valueLimits
            )),
            .interval(try QueryIntervalValue(
                period: CalendarPeriod(months: -2, days: 3),
                time: TimeSpan(seconds: -4, nanoseconds: 0)
            )),
        ]
    }

    private func select(_ expression: Expression) -> QueryStatement {
        .select(SelectQuery(
            projection: .items([ProjectionItem(expression)]),
            source: .table(TableRef("values"))
        ))
    }

    @Test("Named and positional typed NULL preserve the complete declaration")
    func typedNullPreservesDeclaration() throws {
        let parameter = QueryParameter(position: 1, name: "value", value: .primitive(.null), type: .sql(.bigint))
        let binder = try QueryParameterBinder(parameters: [parameter])
        for reference in [QueryParameterReference.position(1), .name("value")] {
            #expect(try binder.bind(select(.parameter(reference))) == select(
                .literal(.queryValue(.primitive(.null), type: .sql(.bigint)))
            ))
        }
        #expect(Literal.queryValue(.primitive(.null), type: .sql(.bigint)).isNull)
    }

    @Test("Explicit empty array parameters keep their element type")
    func emptyArrayPreservesDeclaration() throws {
        let value = QueryValue.array(try QueryArrayValue(
            elementType: .bigint, dimensions: [], elements: [], limits: valueLimits
        ))
        let binder = try QueryParameterBinder(parameters: [
            QueryParameter(position: 1, value: value, type: .sql(.array(.bigint))),
        ])
        #expect(try binder.bind(select(.parameter(.position(1)))) == select(
            .literal(.queryValue(value, type: .sql(.array(.bigint))))
        ))
    }

    @Test("Every rich parameter preserves its metadata in the bound literal")
    func richParametersPreserveValues() throws {
        for value in try richValues() {
            let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: value)])
            #expect(try binder.bind(select(.parameter(.position(1)))) == select(.literal(.queryValue(value))))
        }
    }

    @Test("Direct, array-nested and query-nested rich SQL generation fail explicitly")
    func richSQLGenerationFails() throws {
        for value in try richValues() {
            let literal = Literal.queryValue(value)
            #expect(throws: QueryLiteralConversionError.unsupportedSQLLiteral) {
                _ = try literal.toSQL()
            }
            #expect(throws: QueryLiteralConversionError.unsupportedSQLLiteral) {
                _ = try Literal.array([.int(1), literal]).toSQL()
            }
            #expect(throws: QueryLiteralConversionError.unsupportedSQLLiteral) {
                guard case .select(let query) = select(.add(.literal(.int(1)), .literal(literal))) else {
                    Issue.record("Expected SELECT fixture")
                    return
                }
                _ = try query.toSQL()
            }
        }
    }

    @Test("Wrapped primitive SQL generation follows the existing lossless path")
    func primitiveSQLGenerationPreservesBehavior() throws {
        #expect(try Literal.queryValue(.primitive(.uint64(.max))).toSQL() == String(UInt64.max))
        #expect(try Literal.queryValue(.primitive(.string("a'b"))).toSQL() == "'a''b'")
        #expect(throws: QueryLiteralConversionError.unsupportedFieldValue) {
            _ = try Literal.queryValue(.primitive(.object(FieldObject()))).toSQL()
        }
    }

    @Test("SPARQL rejects each rich value at validation and serialization")
    func richSPARQLValuesFail() throws {
        for value in try richValues() {
            let literal = Literal.queryValue(value)
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
                _ = try Literal.array([.int(1), literal]).toSPARQL()
            }
            let pattern = GraphPattern.filter(.basic([]), .literal(literal))
            #expect(throws: SPARQLSemanticValidationError.unsupportedQueryValue) {
                try SPARQLSemanticValidator.validate(pattern)
            }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
                _ = try pattern.toSPARQL()
            }
        }
    }

    @Test("Primitive SPARQL parameter and NULL conversion retain their semantics")
    func primitiveSPARQLParametersPreserveBehavior() throws {
        let binder = try QueryParameterBinder(parameters: [
            QueryParameter(position: 1, value: .primitive(.bool(true))),
        ])
        let statement = QueryStatement.ask(AskQuery(pattern: .filter(.basic([]), .parameter(.position(1)))))
        #expect(try binder.bind(statement) == .ask(AskQuery(pattern: .filter(.basic([]), .literal(.bool(true))))))
        #expect(try Literal.queryValue(.primitive(.null), type: .sql(.bigint)).toSPARQL() == "UNDEF")
        #expect(try Literal.queryValue(.primitive(.int64(42))).toSPARQL() == "42")
        #expect(Literal.queryValue(.primitive(.int64(2)), type: .sql(.bigint)).compareExactNumeric(to: .int(10)) == -1)
    }

    @Test("Repeated rich payloads consume the cumulative retained-byte budget")
    func repeatedRichValuesConsumeBytes() throws {
        let value = QueryValue.json(try QueryJSONValue(
            bytes: ByteString(Array("{\"x\":1}".utf8)), limits: valueLimits
        ))
        let retainedBytes = try QueryValueValidator.measure(value).retainedByteCount
        let maximumBytes = retainedBytes * 2 - 1
        let binder = try QueryParameterBinder(
            parameters: [QueryParameter(position: 1, value: value)],
            structuralLimits: QueryStructuralLimits(maximumRetainedBytes: maximumBytes)
        )
        #expect(throws: QueryParameterBindingError.invalidStructure(
            .resourceLimitExceeded(resource: .retainedBytes, actual: retainedBytes * 2, maximum: maximumBytes)
        )) {
            _ = try binder.bind(select(.add(.parameter(.position(1)), .parameter(.position(1)))))
        }
    }

    @Test("Rich literal nodes are included in structural admission")
    func richLiteralNodesConsumeBudget() throws {
        let numeric = try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 2)
        let expression = Expression.literal(.queryValue(.numeric(numeric)))
        try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .totalNodes, actual: 3, maximum: 2
        )) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumTotalNodes: 2))
        }
    }

    @Test("Explicit type declarations participate in structural depth admission")
    func typeDeclarationsConsumeDepth() throws {
        let expression = Expression.literal(.queryValue(.primitive(.null), type: .sql(.array(.bigint))))
        try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumNestingDepth: 5))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .nestingDepth, actual: 5, maximum: 4
        )) {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumNestingDepth: 4))
        }
    }
}
