import DatabaseKit
import Testing

@Suite("SQL temporal declaration semantics")
struct SQLTemporalSemanticTests {
    @Test func currentValueIdentityAndBinding() throws {
        let expressions = SQLCurrentValueKind.allCases.map { Expression.currentValue(kind: $0, precision: nil) }
        #expect(Set(expressions).count == 5)
        let precise = Expression.currentValue(kind: .time, precision: 0)
        #expect(precise != .currentValue(kind: .time, precision: nil))
        #expect(precise != .function(FunctionCall(name: "current_time", arguments: [.int(0)])))
        let query = SelectQuery(projection: [ProjectionItem(precise)], source: .values([]), filter: precise)
        let binder = try QueryParameterBinder(parameters: [])
        try binder.validate(.select(query))
        #expect(try binder.bind(.select(query)) == .select(query))
        #expect(query.referencedVariables.isEmpty)
        #expect(query.referencedColumns.isEmpty)
    }

    @Test func currentValueStructuralAdmission() throws {
        for kind in SQLCurrentValueKind.allCases {
            try QueryStructuralValidator.validate(.currentValue(kind: kind, precision: nil), limits: QueryStructuralLimits(maximumTotalNodes: 1))
            for precision in [0, 3, 6] where kind != .date {
                try QueryStructuralValidator.validate(.currentValue(kind: kind, precision: precision), limits: .default)
            }
        }
        for expression: Expression in [.currentValue(kind: .date, precision: 0),
                                       .currentValue(kind: .time, precision: -1),
                                       .currentValue(kind: .timestamp, precision: 7)] {
            #expect(throws: QueryStructuralValidationError.invalidQueryValue(.incompatibleType)) {
                try QueryStructuralValidator.validate(expression, limits: .default)
            }
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(.currentValue(kind: .date, precision: nil), limits: QueryStructuralLimits(maximumTotalNodes: 0))
        }
    }

    @Test func intervalDescriptorIdentity() throws {
        let types = SQLIntervalFields.allCases.map { DataType.interval(fields: $0) }
        #expect(Set(types).count == 13)
        #expect(!Set(types).contains(.interval()))
        for type in types + [.interval(), .interval(precision: 0), .interval(fields: .dayToSecond, precision: 6)] {
            #expect(QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
            try QueryStructuralValidator.validate(.cast(.null, targetType: type), limits: .default)
        }
        for type: DataType in [.interval(precision: -1), .interval(precision: 7), .interval(fields: .year, precision: 3)] {
            #expect(!QueryValueValidator.accepts(.primitive(.null), type: .sql(type)))
            #expect(throws: QueryStructuralValidationError.self) {
                try QueryStructuralValidator.validate(.cast(.null, targetType: type), limits: .default)
            }
        }
    }

    @Test func currentValueLanguageIsolation() throws {
        for kind in SQLCurrentValueKind.allCases {
            let expression = Expression.currentValue(kind: kind, precision: nil)
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try expression.toSPARQL() }
            let query = SelectQuery(projection: [ProjectionItem(expression)], source: .values([]))
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(query) }
        }
    }
}
