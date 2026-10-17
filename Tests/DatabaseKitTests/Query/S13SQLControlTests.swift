import Testing
@testable import DatabaseKit

@Suite("S13 SQL semantic controls and DEFAULT")
struct S13SQLControlTests {
    @Test("DEFAULT remains a distinct intrinsic leaf through all query traversals")
    func defaultLeaf() throws {
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
            try Expression.defaultValue.toSPARQL()
        }
        #expect(Expression.defaultValue != .null)
        #expect(Set([Expression.defaultValue, .null]).count == 2)
        try QueryStructuralValidator.validate(Expression.defaultValue, limits: .init(maximumTotalNodes: 1))
        #expect(QueryReferenceCollector.collect(Expression.defaultValue).columns.isEmpty)
        #expect(QueryReferenceCollector.collect(Expression.defaultValue).variables.isEmpty)
        let query = SelectQuery(projection: [.expression(.defaultValue)], source: .values([[.parameter(.position(1))]]))
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        guard case .select(let bound) = try binder.bind(.select(query)) else { Issue.record("Expected SELECT"); return }
        #expect(bound.projection == [.expression(.defaultValue)])
        #expect(bound.source == .values([[.int(7)]]))
        #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) {
            try SPARQLSemanticValidator.validate(SelectQuery(projection: [.expression(.defaultValue)], source: .table(TableRef("t"))))
        }
    }

    @Test("INSERT identity overriding survives forced parameter reconstruction")
    func identityOverrideBinding() throws {
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        for overriding: SQLIdentityOverride? in [nil, .systemValue, .userValue] {
            let statement = QueryStatement.insert(InsertQuery(target: TableRef("t"),
                source: .values([[.parameter(.position(1)), .defaultValue]]), overriding: overriding))
            guard case .insert(let bound) = try binder.bind(statement) else { Issue.record("Expected INSERT"); return }
            #expect(bound.overriding == overriding)
            #expect(bound.source == .values([[.int(7), .defaultValue]]))
            try QueryStructuralValidator.validate(.insert(bound))
        }
    }

    @Test("SET CONSTRAINTS validates names and contributes cumulative byte and collection costs")
    func constraintControls() throws {
        for names in [[], [""], ["a\u{0}b"]] {
            #expect(throws: SQLCatalogError.self) { try SQLSetConstraints(selection: .named(names), deferred: true) }
        }
        let control = try SQLSetConstraints(selection: .named(["é", "b"]), deferred: true)
        let block = try SQLBlock(steps: [.setConstraints(control), .savepoint("c")],
                                 limits: .init(maximumRetainedBytes: 4, maximumCollectionElements: 4))
        #expect(block.steps[0] == .setConstraints(control))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumRetainedBytes: 3))
        }
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumCollectionElements: 3))
        }
        #expect(!SQLCommandKind.setConstraints.reportsAffectedRows)
    }

    @Test("Sequence commands reject malformed drops and out-of-bound restarts before execution")
    func sequenceControls() throws {
        let sequence = try SQLSequence(id: "s", namespaceID: "n", name: "s", start: 1, increment: 1, minimum: 1, maximum: 3)
        let block = try SQLBlock(steps: [.sequence(.create(sequence)), .sequence(.alter(sequence, restart: 3)), .sequence(.drop(id: "s", cascade: false))])
        #expect(block.steps.count == 3)
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) {
            try SQLBlock(steps: [.sequence(.alter(sequence, restart: 4))])
        }
        for id in ["", "a\u{0}b"] {
            #expect(throws: QueryStructuralValidationError.invalidSQLControl) {
                try SQLBlock(steps: [.sequence(.drop(id: id, cascade: false))])
            }
        }
        for kind: SQLCommandKind in [.createSequence, .alterSequence, .dropSequence] { #expect(!kind.reportsAffectedRows) }
    }
}
