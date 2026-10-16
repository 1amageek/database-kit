import DatabaseKit
import Testing

@Suite("SQL collection declaration semantics")
struct SQLCollectionSemanticTests {
    @Test("Access groups bound presence and all operators preserve structural identity")
    func identity() throws {
        let base = Expression.array([.int(1), .int(2)])
        let shapes: [Expression] = [
            .arrayAccess(base, subscripts: [.index(.int(1))]),
            .arrayAccess(base, subscripts: [.slice(lower: nil, upper: .int(1))]),
            .arrayAccess(base, subscripts: [.slice(lower: .null, upper: .int(1))]),
            .arrayAccess(base, subscripts: [.slice(lower: nil, upper: nil)]),
            .arrayAccess(.arrayAccess(base, subscripts: [.index(.int(1))]), subscripts: [.index(.int(2))]),
            .arrayAccess(base, subscripts: [.index(.int(1)), .index(.int(2))]),
        ]
        #expect(Set(shapes).count == shapes.count)
        let operators = (UInt8(0)...10).compactMap(CollectionOperator.init(rawValue:))
        let values = operators.map { Expression.collectionOperation($0, left: base, right: .null) }
        #expect(values.count == 11 && Set(values).count == 11)
        let plain = Expression.function(FunctionCall(name: "jsonb_build_array", arguments: [base]))
        let expanded = Expression.function(FunctionCall(name: "jsonb_build_array", arguments: [base], finalArrayIsVariadic: true))
        #expect(plain != expanded && Set([plain, expanded]).count == 2)
        func deep(_ leaf: Expression) -> Expression {
            var value = leaf
            for _ in 0..<512 { value = .arrayAccess(value, subscripts: [.slice(lower: nil, upper: .int(1))]) }
            return value
        }
        #expect(deep(plain) == deep(plain))
        #expect(deep(plain) != deep(expanded))
        #expect(Set([deep(plain), deep(plain)]).count == 1)
    }

    @Test("Parameter rebuilding reaches every bound and preserves variadic function metadata")
    func parameterRebuilding() throws {
        let access = Expression.arrayAccess(.parameter(.position(1)), subscripts: [
            .index(.parameter(.position(2))), .slice(lower: .parameter(.position(3)), upper: .parameter(.position(4))),
            .slice(lower: nil, upper: nil),
        ])
        let function = Expression.function(FunctionCall(name: "f", arguments: [access], distinct: true,
            schema: "qualified", finalArrayIsVariadic: true))
        let expression = Expression.collectionOperation(.contains, left: function, right: .parameter(.position(5)))
        let query = SelectQuery(projection: [ProjectionItem(expression)], source: .values([]))
        let parameters = (1...5).map { QueryParameter(position: UInt32($0), value: .primitive(.int64(Int64($0)))) }
        let binder = try QueryParameterBinder(parameters: parameters)
        guard case .select(let bound) = try binder.bind(.select(query)), case .expression(.collectionOperation(.contains, let left, let right), _) = bound.projection[0],
              case .function(let rebuilt) = left,
              case .arrayAccess(let base, let subscripts) = rebuilt.arguments[0] else {
            Issue.record("Lost collection expression during parameter replacement"); return
        }
        #expect(rebuilt.finalArrayIsVariadic && rebuilt.distinct && rebuilt.schema == "qualified")
        #expect(base == .literal(.int(1)))
        #expect(subscripts == [.index(.literal(.int(2))), .slice(lower: .literal(.int(3)), upper: .literal(.int(4))),
                               .slice(lower: nil, upper: nil)])
        #expect(right == .literal(.int(5)))
        #expect(throws: QueryParameterBindingError.missingPosition(4)) {
            try QueryParameterBinder(parameters: parameters.filter { $0.position != 4 }).validate(.select(query))
        }
    }

    @Test("Every access child participates in reference and exact structural admission")
    func referenceAndStructuralAdmission() throws {
        let expression = Expression.collectionOperation(.jsonPath, left: .arrayAccess(.col("base"), subscripts: [
            .index(.col("index")), .slice(lower: .col("lower"), upper: .col("upper")),
        ]), right: .col("path"))
        let query = SelectQuery(projection: [ProjectionItem(expression)], source: .values([]))
        #expect(query.referencedColumns == Set(["base", "index", "lower", "upper", "path"].map(ColumnRef.init)))
        let value = Expression.arrayAccess(.parameter(.position(1)), subscripts: [.slice(lower: .parameter(.position(2)), upper: .parameter(.position(3)))])
        try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumTotalNodes: 4, maximumCollectionElements: 1))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumTotalNodes: 3))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(value, limits: QueryStructuralLimits(maximumCollectionElements: 0))
        }
        for count in [0, 7] {
            #expect(throws: QueryStructuralValidationError.invalidArrayAccessSubscriptCount(count)) {
                try QueryStructuralValidator.validate(.arrayAccess(.null, subscripts: Array(repeating: .index(.null), count: count)))
            }
        }
        #expect(throws: QueryStructuralValidationError.emptyVariadicFunctionArguments) {
            try QueryStructuralValidator.validate(.function(FunctionCall(name: "f", arguments: [], finalArrayIsVariadic: true)))
        }
    }

    @Test("SQL collection and explicit variadic forms never acquire SPARQL semantics")
    func languageIsolation() throws {
        let values: [Expression] = [
            .arrayAccess(.null, subscripts: [.index(.null)]),
            .collectionOperation(.contains, left: .null, right: .null),
            .function(FunctionCall(name: "f", arguments: [.null], finalArrayIsVariadic: true)),
        ]
        for value in values {
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { try value.toSPARQL() }
            let query = SelectQuery(projection: [ProjectionItem(value)], source: .values([]))
            #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(query) }
        }
    }

    @Test("New collection left/right occurrences remain distinct from existing operand edges")
    func occurrenceRoles() throws {
        var arena = QueryOccurrenceArena()
        let root = try arena.append()
        let left = try arena.append(parent: root, field: .left)
        let right = try arena.append(parent: root, field: .right)
        let operand = try arena.append(parent: root, field: .operand, index: 0)
        let lower = try arena.append(parent: left, field: .argument, index: 2)
        let upper = try arena.append(parent: left, field: .argument, index: 3)
        #expect(arena.child(of: root, field: .left) == left)
        #expect(arena.child(of: root, field: .right) == right)
        #expect(arena.child(of: root, field: .operand, index: 0) == operand)
        #expect(arena.child(of: left, field: .argument, index: 2) == lower)
        #expect(arena.child(of: left, field: .argument, index: 3) == upper)
        #expect(Set([left, right, operand, lower, upper]).count == 5)
    }
}
