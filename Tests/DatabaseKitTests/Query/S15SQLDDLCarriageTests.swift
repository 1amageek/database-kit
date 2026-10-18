import DatabaseKit
import DatabaseTypes
import Testing

@Suite("S15 SQL DDL declaration carriage")
struct S15SQLDDLCarriageTests {
    private func query(_ value: Expression) -> SelectQuery {
        SelectQuery(projection: [.expression(value, alias: "value")], source: .values([[]]))
    }

    private func fixtures(_ value: (UInt32) -> Expression) -> [QueryStatement] {
        [
            .ddl(.createTable(SQLCreateTable(name: TableRef(schema: "app", table: "items"), source: .columns([
                SQLColumnDefinition(name: "a", type: .integer, policy: .input(defaultExpression: value(1))),
                SQLColumnDefinition(name: "b", type: .integer, policy: .generated(value(2), stored: true), constraints: [
                    SQLTableConstraint(name: "b_check", kind: .check(value(3))),
                ]),
            ], constraints: [SQLTableConstraint(name: "table_check", kind: .check(value(4)))]), temporary: true, ifNotExists: true))),
            .ddl(.alterTable(SQLAlterTable(name: TableRef("items"), actions: [
                .addColumn(SQLColumnDefinition(name: "c", type: .integer, policy: .input(defaultExpression: value(5)),
                    constraints: [SQLTableConstraint(kind: .check(value(6)))]), ifNotExists: true),
                .alterColumnType(name: "a", type: .bigint, using: value(7)),
                .setDefault(column: "a", expression: value(8)),
                .addConstraint(SQLTableConstraint(name: "new_check", kind: .check(value(9)))),
            ], ifExists: true))),
            .ddl(.createIndex(SQLCreateIndex(name: TableRef("ordered"), table: TableRef("items"),
                keys: [SortKey(value(10), direction: .descending, nulls: .first)], predicate: value(11), unique: true, nulls: .notDistinct, ifNotExists: true))),
            .ddl(.createTable(SQLCreateTable(name: TableRef("copied"), source: .query(query(value(12)), columns: ["a"], withData: false)))),
            .ddl(.createView(SQLCreateView(name: TableRef("visible"), columns: ["a"], query: query(value(13)), orReplace: true))),
            .ddl(.createMaterializedView(SQLCreateMaterializedView(name: TableRef("cached"), columns: ["a"], query: query(value(14)), withData: false, ifNotExists: true))),
        ]
    }

    @Test("Every DDL expression and SELECT body participates in forced parameter substitution")
    func allChildrenBind() throws {
        let original = fixtures { .parameter(position: $0) }
        let expected = fixtures { .int(Int64($0)) }
        let parameters = (1...14).map { QueryParameter(position: UInt32($0), value: .primitive(.int64(Int64($0)))) }
        let binder = try QueryParameterBinder(parameters: parameters)
        for index in original.indices {
            try binder.validate(original[index])
            #expect(try binder.bind(original[index]) == expected[index])
        }
        for missing in 1...14 {
            let incomplete = try QueryParameterBinder(parameters: parameters.filter { $0.position != UInt32(missing) })
            var failures = 0
            for statement in original {
                do { try incomplete.validate(statement) }
                catch QueryParameterBindingError.missingPosition(let position) where position == UInt32(missing) { failures += 1 }
            }
            #expect(failures == 1)
        }
    }

    @Test("DDL identity retains exact UTF8 names and all non-expression metadata")
    func exactIdentity() throws {
        let composed = "\u{00E9}", decomposed = "e\u{0301}"
        let left = QueryStatement.ddl(.createSchema(name: composed, ifNotExists: true))
        let right = QueryStatement.ddl(.createSchema(name: decomposed, ifNotExists: true))
        #expect(left != right)
        #expect(Set([left, right]).count == 2)
        let targetLeft = QueryStatement.ddl(.dropView(names: [TableRef(schema: composed, table: "v")], ifExists: true, behavior: .cascade))
        let targetRight = QueryStatement.ddl(.dropView(names: [TableRef(schema: decomposed, table: "v")], ifExists: true, behavior: .cascade))
        #expect(targetLeft != targetRight)
        #expect(Set([targetLeft, targetRight]).count == 2)
        let options = SQLSequenceOptions(type: .smallint, start: -3, increment: -2, minimum: .value(-10), maximum: .some(.none), cycle: true)
        let declaration = SQLDDLStatement.alterSequence(SQLAlterSequence(name: TableRef("s"), options: options,
            restart: .start, ownedBy: .some(.none), renameTo: "next", ifExists: true))
        try QueryStructuralValidator.validate(.ddl(declaration))
        #expect(declaration == .alterSequence(SQLAlterSequence(name: TableRef("s"), options: options,
            restart: .start, ownedBy: .some(.none), renameTo: "next", ifExists: true)))
        #expect(declaration != .alterSequence(SQLAlterSequence(name: TableRef("s"), options: options,
            restart: .value(-3), ownedBy: .some(.none), renameTo: "next", ifExists: true)))
        #expect(fixtures { .int(Int64($0)) } == fixtures { .int(Int64($0)) })
    }

    @Test("Malformed intrinsic DDL shapes fail explicitly")
    func invalidShapes() {
        let target = TableRef("items")
        let invalid: [SQLDDLStatement] = [
            .createSchema(name: "", ifNotExists: false),
            .dropSchema(names: [], ifExists: false, behavior: .restrict),
            .dropTable(names: [], ifExists: false, behavior: .restrict),
            .alterTable(SQLAlterTable(name: target, actions: [])),
            .createView(SQLCreateView(name: TableRef(table: "v", alias: "x"), query: query(.int(1)))),
            .createView(SQLCreateView(name: target, columns: ["a", "a"], query: query(.int(1)))),
            .createIndex(SQLCreateIndex(name: target, table: target, keys: [])),
            .createIndex(SQLCreateIndex(name: TableRef(schema: "app", table: "i"), table: target, keys: [SortKey(.int(1))])),
            .createIndex(SQLCreateIndex(name: target, table: target, keys: [SortKey(.int(1))], nulls: .notDistinct)),
            .createTable(SQLCreateTable(name: target, source: .columns([SQLColumnDefinition(name: "a", type: .text, policy: .serial)], constraints: []))),
            .createTable(SQLCreateTable(name: target, source: .columns([SQLColumnDefinition(name: "a", type: .integer,
                constraints: [SQLTableConstraint(kind: .notNull(column: "b"))])], constraints: []))),
            .createTable(SQLCreateTable(name: target, source: .columns([], constraints: [SQLTableConstraint(timing: .deferrable(initiallyDeferred: true), kind: .check(.bool(true)))]))),
            .createSequence(SQLCreateSequence(name: target, options: SQLSequenceOptions(increment: 0))),
            .createSequence(SQLCreateSequence(name: target, options: SQLSequenceOptions(type: .text))),
            .createSequence(SQLCreateSequence(name: target, options: SQLSequenceOptions(minimum: .value(5), maximum: .value(4)))),
        ]
        for declaration in invalid {
            #expect(throws: QueryStructuralValidationError.invalidSQLDDL) { try QueryStructuralValidator.validate(.ddl(declaration)) }
        }
    }

    @Test("DDL metadata and nested values consume the same cumulative admission ledger")
    func cumulativeLimits() throws {
        let first = QueryStatement.ddl(.createSchema(name: "abc", ifNotExists: false))
        try QueryStructuralValidator.validate(first, limits: QueryStructuralLimits(maximumRetainedBytes: 3, maximumTotalNodes: 1))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(first, limits: QueryStructuralLimits(maximumRetainedBytes: 2))
        }
        let block = try SQLBlock(steps: [.statement(first), .statement(first)])
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(block, limits: QueryStructuralLimits(maximumRetainedBytes: 5))
        }
        let statement = fixtures { .int(Int64($0)) }[0]
        for limits in [QueryStructuralLimits(maximumRetainedBytes: 1), QueryStructuralLimits(maximumTotalNodes: 1),
                       QueryStructuralLimits(maximumCollectionElements: 1), QueryStructuralLimits(maximumNestingDepth: 1)] {
            #expect(throws: QueryStructuralValidationError.self) { try QueryStructuralValidator.validate(statement, limits: limits) }
        }
    }

    @Test("Deep DDL expression and SELECT mixtures reuse bounded iterative traversal")
    func deepChildren() throws {
        var expression = Expression.parameter(position: 1)
        var expected = Expression.int(7)
        for _ in 0..<180 { expression = .add(expression, .int(1)); expected = .add(expected, .int(1)) }
        let original = QueryStatement.ddl(.createView(SQLCreateView(name: TableRef("v"), query: query(expression))))
        let replacement = QueryStatement.ddl(.createView(SQLCreateView(name: TableRef("v"), query: query(expected))))
        let limits = QueryStructuralLimits(maximumNestingDepth: 1024)
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))], structuralLimits: limits)
        #expect(try binder.bind(original) == replacement)
        #expect(original != replacement)
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(original, limits: QueryStructuralLimits(maximumNestingDepth: 180))
        }
    }

    @Test("DDL classification and SQL-only SPARQL rejection preserve schema meaning")
    func classification() throws {
        let statement = QueryStatement.ddl(.refreshMaterializedView(name: TableRef("cached"), withData: false))
        #expect(statement.isSchemaDefinition)
        #expect(!statement.isModification)
        #expect(!statement.isReadOnly)
        #expect(!SQLCommandKind.refreshMaterializedView.reportsAffectedRows)
        #expect(SQLDDLStatement.renameSchema(name: "a", to: "b").command == .alterSchema)
        #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) { try SPARQLSemanticValidator.validate(statement) }
    }

    @Test("Column renaming preserves exact identity, parameters and nested lexical scope")
    func scalarColumnRenaming() throws {
        let nested = query(.column(ColumnRef("old")))
        let expression = Expression.add(.column(ColumnRef("old")), .add(.parameter(position: 1), .subquery(nested)))
        let expected = Expression.add(.column(ColumnRef("new")), .add(.parameter(position: 1), .subquery(nested)))
        #expect(try QueryColumnRenaming.rename(expression, from: ColumnRef("old"), to: ColumnRef("new")) == expected)
        #expect(try QueryColumnRenaming.rename(.column(ColumnRef("e\u{0301}")),
            from: ColumnRef("\u{00E9}"), to: ColumnRef("new")) == .column(ColumnRef("e\u{0301}")))
        #expect(try QueryColumnRenaming.rename(.column(ColumnRef(table: "t", column: "old")),
            from: ColumnRef("old"), to: ColumnRef("new")) == .column(ColumnRef(table: "t", column: "old")))
    }
}
