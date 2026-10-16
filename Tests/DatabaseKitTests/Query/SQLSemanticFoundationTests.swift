import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL semantic foundation")
struct SQLSemanticFoundationTests {
    @Test("SQL unknown strings retain distinct semantic identity and reject RDF conversion")
    func unknownStringIdentity() throws {
        let literal = Literal.sqlUnknownString("同じ")
        #expect(literal != .string("同じ"))
        #expect(literal.xsdDatatype == nil)
        #expect(literal.stringValue == nil)
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try literal.toSPARQL() }
        #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) {
            try SPARQLSemanticValidator.validate(sparqlQuery(.literal(literal)))
        }
        try SPARQLSemanticValidator.validate(sparqlQuery(.literal(.string("同じ"))))
    }

    @Test("Parameter validation admits occurrences without substituting and binding preserves schemas")
    func parameterValidationAndQualifiedFunction() throws {
        let expression = Expression.function(FunctionCall(name: "Exact.F", arguments: [.parameter(.position(1))], schema: "Exact.Schema"))
        let statement = QueryStatement.select(SelectQuery(projection: [ProjectionItem(expression)], source: .values([])))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        try binder.validate(statement)
        guard case .select(let query) = try binder.bind(statement),
              case .expression(.function(let function), _) = query.projection[0] else {
            Issue.record("Binding lost the function expression")
            return
        }
        #expect(function.schema == "Exact.Schema")
        #expect(function.name == "Exact.F")
        #expect(function.arguments == [.literal(.int(7))])
        #expect(throws: QueryParameterBindingError.missingPosition(1)) {
            try QueryParameterBinder(parameters: []).validate(statement)
        }
    }

    @Test("SQL schema qualifiers cannot acquire SPARQL meaning")
    func qualifiedNamesRejectSPARQL() throws {
        #expect(try DataType.custom("custom:Type").sparqlFunction == "custom:Type")
        #expect(try DataType.time(withTimeZone: false).sparqlFunction == "xsd:time")
        #expect(try DataType.array(.custom("custom:Type")).sparqlFunction == "xsd:string")
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
            try DataType.custom("T", schema: "S").sparqlFunction
        }
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
            try DataType.array(.custom("T", schema: "S")).sparqlFunction
        }
        let expressions: [Expression] = [
            .function(FunctionCall(name: "F", arguments: [], schema: "S")),
            .cast(.int(1), targetType: .array(.custom("T", schema: "S"))),
        ]
        for expression in expressions {
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(sparqlQuery(expression)) }
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try expression.toSPARQL() }
        }
    }

    @Test("New SQL strings and qualifier bytes use exact and one-past structural admission")
    func retainedStringBoundaries() throws {
        let expressions: [Expression] = [
            .literal(.sqlUnknownString("é")),
            .function(FunctionCall(name: "f", arguments: [], schema: "é")),
            .cast(.int(1), targetType: .custom("t", schema: "é")),
        ]
        for expression in expressions {
            try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumRetainedBytes: 2))
            #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .retainedBytes, actual: 2, maximum: 1)) {
                try QueryStructuralValidator.validate(expression, limits: QueryStructuralLimits(maximumRetainedBytes: 1))
            }
        }
    }

    @Test("Occurrence storage rejects one-past its defined logical byte budget")
    func occurrenceStorageBoundary() throws {
        var measured = QueryOccurrenceArena()
        _ = try measured.append()
        let bytes = QueryStructuralLimits.default.maximumRetainedBytes - measured.remainingLimits.maximumRetainedBytes
        var exact = QueryOccurrenceArena(limits: QueryStructuralLimits(maximumRetainedBytes: bytes))
        _ = try exact.append()
        #expect(exact.remainingLimits.maximumRetainedBytes == 0)
        var short = QueryOccurrenceArena(limits: QueryStructuralLimits(maximumRetainedBytes: bytes - 1))
        #expect(throws: QueryOccurrenceError.resourceLimit(.resourceLimitExceeded(resource: .retainedBytes, actual: bytes, maximum: bytes - 1))) {
            try short.append()
        }
        #expect(short.count == 0)
        #expect(short.remainingLimits.maximumRetainedBytes == bytes - 1)
    }

    @Test("Occurrence edges distinguish equal nodes and rejected claims preserve the arena")
    func occurrenceIdentityAndBoundaries() throws {
        var arena = QueryOccurrenceArena(limits: QueryStructuralLimits(maximumTotalNodes: 3))
        let root = try arena.append()
        let first = try arena.append(parent: root, field: .projection, index: 0)
        let second = try arena.append(parent: root, field: .projection, index: 1)
        #expect(first != second)
        #expect(arena.child(of: root, field: .projection, index: 0) == first)
        #expect(arena.child(of: root, field: .projection, index: 1) == second)
        #expect(throws: QueryOccurrenceError.duplicateOccurrence) { try arena.append(parent: root, field: .projection, index: 0) }
        #expect(throws: QueryOccurrenceError.self) { try arena.append(parent: root, field: .filter) }
        #expect(arena.count == 3)
        #expect(arena.child(of: root, field: .filter) == nil)
        #expect(throws: QueryOccurrenceError.invalidParent(QueryOccurrenceID(rawValue: 99))) {
            try arena.append(parent: QueryOccurrenceID(rawValue: 99), field: .operand, index: 0)
        }
        let maximumID = QueryOccurrenceID(rawValue: .max)
        #expect(arena.occurrence(maximumID) == nil)
        #expect(throws: QueryOccurrenceError.invalidParent(maximumID)) {
            try arena.append(parent: maximumID, field: .operand, index: 0)
        }
        #expect(arena.count == 3)
        var shallow = QueryOccurrenceArena(limits: QueryStructuralLimits(maximumNestingDepth: 0))
        let shallowRoot = try shallow.append()
        #expect(throws: QueryOccurrenceError.self) { try shallow.append(parent: shallowRoot, field: .filter) }
        #expect(shallow.count == 1)
    }
    private func sparqlQuery(_ expression: Expression) -> SelectQuery {
        SelectQuery(projection: [ProjectionItem(expression, alias: "value")], source: .graphPattern(.basic([])))
    }

}
