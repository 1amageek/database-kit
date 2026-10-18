import DatabaseTypes
import DatabaseKit
import Testing

@Suite("S14 SQL mutation declaration carriage")
struct S14SQLMutationCarriageTests {
    private let aliases = SQLReturningAliases(old: "prior", new: "next")

    private func fixture(_ value: (UInt32) -> Expression) -> QueryStatement {
        let insert = QueryStatement.insert(InsertQuery(target: TableRef("t"), columns: ["a"],
            source: .values([[value(1)]]),
            onConflict: .doUpdate(assignments: [Assignment(columns: ["a", "b"], value: .row([value(3), value(4)]))], where: value(5)),
            returning: [.expression(value(6))], overriding: .systemValue,
            conflictTarget: .columns(["a"], where: value(2)), returningAliases: aliases))
        let update = QueryStatement.update(UpdateQuery(target: TableRef("t"),
            assignments: [Assignment(column: "a", value: value(7))], from: .values([[value(8)]]),
            filter: value(9), returning: [.expression(value(10))], returningAliases: aliases))
        let delete = QueryStatement.delete(DeleteQuery(target: TableRef("t"), using: .values([[value(11)]]),
            filter: value(12), returning: [.expression(value(13))], returningAliases: aliases))
        let merge = QueryStatement.merge(MergeQuery(target: TableRef("t"), source: .values([[value(14)]]),
            condition: value(15), clauses: [
                SQLMergeClause(match: .matched, condition: value(16),
                    action: .update([Assignment(columns: ["a", "b"], value: .row([value(17), value(18)]))])),
                SQLMergeClause(match: .notMatchedByTarget,
                    action: .insert(columns: ["a"], values: [value(19)], overriding: .userValue)),
                SQLMergeClause(match: .notMatchedBySource, action: .delete),
                SQLMergeClause(match: .matched, action: .doNothing),
            ], returning: [.expression(value(20))], returningAliases: aliases))
        return .with(SQLWithStatement(recursive: true, statements: [
            SQLNamedStatement(name: "inserted", columns: ["a"], statement: insert, materialized: .materialized,
                search: CTESearchClause(order: .depthFirst, columns: ["a"], sequenceColumn: "sequence"),
                cycle: CTECycleClause(columns: ["a"], markColumn: "cycle", pathColumn: "path",
                    markValue: .bool(true), defaultValue: .bool(false))),
            SQLNamedStatement(name: "updated", statement: update, materialized: .notMaterialized),
            SQLNamedStatement(name: "deleted", statement: delete),
        ], body: merge))
    }

    @Test("Forced substitution reconstructs every mutation child and retains all metadata")
    func everyChildBinds() throws {
        let statement = fixture { .parameter(position: $0) }
        let parameters = (1...20).map { QueryParameter(position: UInt32($0), value: .primitive(.int64(Int64($0)))) }
        let binder = try QueryParameterBinder(parameters: parameters)
        try binder.validate(statement)
        #expect(try binder.bind(statement) == fixture { .int(Int64($0)) })
        for missing in 1...20 {
            let incomplete = try QueryParameterBinder(parameters: parameters.filter { $0.position != UInt32(missing) })
            #expect(throws: QueryParameterBindingError.missingPosition(UInt32(missing))) { try incomplete.validate(statement) }
        }
    }

    @Test("Mutation identity distinguishes target tuples conflict metadata aliases and defaults")
    func identityPreservesMetadata() {
        let first = fixture { .int(Int64($0)) }
        let second = fixture { .int(Int64($0)) }
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        #expect(first != fixture { $0 == 19 ? .int(-1) : .int(Int64($0)) })
        #expect(Assignment(column: "a", value: .int(1)) == Assignment(columns: ["a"], value: .int(1)))
        #expect(Assignment(columns: ["a", "b"], value: .row([.int(1), .int(2)])) != Assignment(columns: ["b", "a"], value: .row([.int(1), .int(2)])))
        let target = TableRef("t")
        #expect(QueryStatement.insert(InsertQuery(target: target, source: .defaultValues, onConflict: .doNothing,
            conflictTarget: .constraint("one"))) != .insert(InsertQuery(target: target, source: .defaultValues,
                onConflict: .doNothing, conflictTarget: .constraint("two"))))
        #expect(SQLReturningAliases(old: "x") != SQLReturningAliases(new: "x"))
        let composed = "\u{00E9}", decomposed = "e\u{0301}"
        #expect(SQLReturningAliases(old: composed) != SQLReturningAliases(old: decomposed))
        #expect(SQLConflictTarget.constraint(composed) != SQLConflictTarget.constraint(decomposed))
        #expect(SQLConflictTarget.columns([composed], where: nil) != SQLConflictTarget.columns([decomposed], where: nil))
        #expect(Assignment(column: composed, value: .int(1)) != Assignment(column: decomposed, value: .int(1)))
        #expect(SQLMergeAction.insert(columns: [composed], values: [.int(1)], overriding: nil) != .insert(columns: [decomposed], values: [.int(1)], overriding: nil))
        let body = QueryStatement.delete(DeleteQuery(target: target))
        #expect(SQLNamedStatement(name: composed, statement: body) != SQLNamedStatement(name: decomposed, statement: body))
        #expect(QueryStatement.with(SQLWithStatement(statements: [SQLNamedStatement(name: composed, statement: body)], body: body)) !=
            .with(SQLWithStatement(statements: [SQLNamedStatement(name: decomposed, statement: body)], body: body)))
        #expect(SQLMergeAction.insert(columns: nil, values: nil, overriding: nil) != .insert(columns: nil, values: [], overriding: nil))
        #expect(QueryStatement.truncate(TruncateQuery(tables: [target])) != .truncate(TruncateQuery(tables: [target], identity: .restart)))
    }

    @Test("WITH classifies writable definitions independently of a read-only body")
    func statementClassification() {
        let select = QueryStatement.select(SelectQuery(projection: [.expression(.int(1))], source: .values([])))
        let readOnly = QueryStatement.with(SQLWithStatement(statements: [SQLNamedStatement(name: "q", statement: select)], body: select))
        #expect(readOnly.isReadOnly)
        #expect(!readOnly.isModification)
        let writable = QueryStatement.with(SQLWithStatement(statements: [SQLNamedStatement(name: "q",
            statement: .delete(DeleteQuery(target: TableRef("t"))))], body: select))
        #expect(!writable.isReadOnly)
        #expect(writable.isModification)
        #expect(fixture { .int(Int64($0)) }.isModification)
        #expect(QueryStatement.truncate(TruncateQuery(tables: [TableRef("t")])).isModification)
    }

    @Test("Intrinsic invalid mutation shapes reject instead of becoming repaired statements")
    func invalidShapes() throws {
        let target = TableRef("t")
        let invalid: [QueryStatement] = [
            .update(UpdateQuery(target: target, assignments: [])),
            .update(UpdateQuery(target: target, assignments: [Assignment(columns: [], value: .int(1))])),
            .update(UpdateQuery(target: target, assignments: [Assignment(columns: ["a", "b"], value: .row([.int(1)]))])),
            .insert(InsertQuery(target: target, source: .values([]))),
            .insert(InsertQuery(target: target, source: .values([[.int(1)], []]))),
            .insert(InsertQuery(target: target, source: .defaultValues, conflictTarget: .constraint("key"))),
            .insert(InsertQuery(target: target, source: .defaultValues,
                onConflict: .doUpdate(assignments: [Assignment(column: "a", value: .int(1))], where: nil))),
            .insert(InsertQuery(target: target, source: .defaultValues, onConflict: .doNothing, conflictTarget: .columns([], where: nil))),
            .delete(DeleteQuery(target: target, returning: [])),
            .delete(DeleteQuery(target: target, returningAliases: aliases)),
            .delete(DeleteQuery(target: target, returning: [.wildcard()], returningAliases: SQLReturningAliases())),
            .delete(DeleteQuery(target: target, returning: [.wildcard()], returningAliases: SQLReturningAliases(old: ""))),
            .with(SQLWithStatement(statements: [], body: .delete(DeleteQuery(target: target)))),
            .merge(MergeQuery(target: target, source: .values([]), condition: .bool(true), clauses: [])),
            .merge(MergeQuery(target: target, source: .values([]), condition: .bool(true), clauses: [
                SQLMergeClause(match: .notMatchedByTarget, action: .insert(columns: ["a"], values: nil, overriding: nil)),
            ])),
            .truncate(TruncateQuery(tables: [])),
        ]
        let select = QueryStatement.select(SelectQuery(projection: [.expression(.int(1))], source: .values([])))
        let invalidMetadata = [
            SQLNamedStatement(name: "q", columns: ["a"], statement: select,
                search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "a")),
            SQLNamedStatement(name: "q", columns: ["a"], statement: select,
                cycle: CTECycleClause(columns: ["k"], markColumn: "a", pathColumn: "p")),
            SQLNamedStatement(name: "q", columns: ["a"], statement: select,
                cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "a")),
            SQLNamedStatement(name: "q", statement: select,
                search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "m"),
                cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p")),
        ]
        for definition in invalidMetadata {
            let statement = QueryStatement.with(SQLWithStatement(statements: [definition], body: .delete(DeleteQuery(target: target))))
            #expect(throws: QueryStructuralValidationError.self) { try QueryStructuralValidator.validate(statement) }
        }
        for statement in invalid {
            #expect(throws: QueryStructuralValidationError.self) { try QueryStructuralValidator.validate(statement) }
        }
    }

    @Test("Deep statement identity hash reconstruction and structural admission use explicit traversal")
    func deepWithCarriage() throws {
        func deep(_ value: Expression) -> QueryStatement {
            var statement = QueryStatement.update(UpdateQuery(target: TableRef("t"), assignments: [Assignment(column: "a", value: value)]))
            for _ in 0..<200 {
                statement = .with(SQLWithStatement(statements: [SQLNamedStatement(name: "q", statement:
                    .truncate(TruncateQuery(tables: [TableRef("t")])) )], body: statement))
            }
            return statement
        }
        let statement = deep(.parameter(position: 1))
        let limits = QueryStructuralLimits(maximumNestingDepth: 1024)
        try QueryStructuralValidator.validate(statement, limits: limits)
        #expect(statement == deep(.parameter(position: 1)))
        #expect(statement.hashValue == deep(.parameter(position: 1)).hashValue)
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))], structuralLimits: limits)
        #expect(try binder.bind(statement) == deep(.int(7)))
        for restricted in [QueryStructuralLimits(maximumNestingDepth: 200),
                           QueryStructuralLimits(maximumNestingDepth: 1024, maximumRetainedBytes: 1),
                           QueryStructuralLimits(maximumNestingDepth: 1024, maximumTotalNodes: 200),
                           QueryStructuralLimits(maximumNestingDepth: 1024, maximumCollectionElements: 200)] {
            #expect(throws: QueryStructuralValidationError.self) { try QueryStructuralValidator.validate(statement, limits: restricted) }
        }
    }

    @Test("Statement WITH MERGE and TRUNCATE explicitly reject SPARQL admission")
    func sqlOnlyStatementsRejectSPARQL() throws {
        for statement in [fixture { .int(Int64($0)) },
            QueryStatement.merge(MergeQuery(target: TableRef("t"), source: .values([]), condition: .bool(true),
                clauses: [SQLMergeClause(match: .matched, action: .doNothing)])),
            .truncate(TruncateQuery(tables: [TableRef("t")]))] {
            #expect(throws: SPARQLSemanticValidationError.self) { try SPARQLSemanticValidator.validate(statement) }
        }
    }
}
