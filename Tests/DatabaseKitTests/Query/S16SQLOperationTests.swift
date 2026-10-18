import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("S16 operational declarations and independent parameter scopes")
struct S16SQLOperationTests {
    private func statement(_ value: Expression = .int(1)) -> QueryStatement {
        .select(SelectQuery(projection: [.expression(value)], source: .values([])))
    }

    @Test("Transaction terminals are admitted before any runtime effects")
    func terminalOrder() throws {
        for steps: [SQLBlockStep] in [
            [.transaction(.begin), .statement(statement()), .transaction(.commit)],
            [.transaction(.begin), .transaction(.rollback)], [.transaction(.commit)], [.transaction(.rollback)],
        ] { _ = try SQLBlock(steps: steps) }
        for steps: [SQLBlockStep] in [
            [.transaction(.begin)], [.statement(statement()), .transaction(.begin), .transaction(.commit)],
            [.transaction(.commit), .statement(statement())], [.transaction(.rollback), .transaction(.begin)],
            [.transaction(.begin), .transaction(.begin), .transaction(.rollback)],
        ] {
            #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLBlock(steps: steps) }
        }
    }

    @Test("Operational names and custom declared type names retain exact UTF-8 identity")
    func exactIdentity() throws {
        let a = "é", b = "e\u{0301}"
        let pairs: [(SQLBlockStep, SQLBlockStep)] = [
            (.prepare(.init(name: a, statement: statement())), .prepare(.init(name: b, statement: statement()))),
            (.execute(.init(name: a)), .execute(.init(name: b))), (.deallocate(a), .deallocate(b)),
            (.prepare(.init(name: "p", parameterTypes: [.array(.custom(a))], statement: statement())),
             .prepare(.init(name: "p", parameterTypes: [.array(.custom(b))], statement: statement()))),
            (.copy(.init(target: .table(TableRef(a), columns: [a]), direction: .to)),
             .copy(.init(target: .table(TableRef(b), columns: [b]), direction: .to))),
        ]
        for (left, right) in pairs { #expect(left != right); #expect(Set([left, right]).count == 2) }
        #expect(SQLBlockStep.deallocate(nil) != .deallocate("ALL"))
    }

    @Test("Prepared names and COPY columns reject malformed intrinsic payloads")
    func invalidNames() throws {
        for name in ["", "a\u{0}b"] {
            for step: SQLBlockStep in [.prepare(.init(name: name, statement: statement())), .execute(.init(name: name)), .deallocate(name)] {
                #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLBlock(steps: [step]) }
            }
        }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) {
            try SQLBlock(steps: [.copy(.init(target: .table(TableRef("t"), columns: ["c", "c"]), direction: .to))])
        }
    }

    @Test("COPY format defaults and explicit custom quoting remain semantic values")
    func copyDefaults() throws {
        #expect(try SQLCopyOptions() == .default)
        #expect(SQLCopyOptions.default.delimiter == "\t")
        #expect(SQLCopyOptions.default.null == "\\N")
        let csv = try SQLCopyOptions(format: .csv)
        #expect(csv.delimiter == ","); #expect(csv.null == ""); #expect(csv.quote == "\""); #expect(csv.escape == "\"")
        let custom = try SQLCopyOptions(format: .csv, delimiter: "|", null: "NULL", header: true, quote: "'", escape: "\\")
        #expect(custom.header); #expect(custom.delimiter == "|"); #expect(custom.escape == "\\")
    }

    @Test("COPY rejects invalid byte options instead of silently normalizing")
    func invalidCopyOptions() throws {
        for delimiter in ["", "é", "\n", "\r", "\u{0}", "aa"] {
            #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(format: .csv, delimiter: delimiter) }
        }
        for delimiter in ["\\", ".", "a", "0"] {
            #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(delimiter: delimiter) }
        }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(header: true) }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(quote: "\"") }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(escape: "\"") }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(format: .csv, delimiter: "\"") }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(format: .csv, null: "a,b") }
        #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLCopyOptions(format: .csv, null: "\"") }
    }

    @Test("COPY direction distinguishes missing bytes from empty retained input")
    func copyDirection() throws {
        let table = SQLCopyTarget.table(TableRef("t"), columns: [])
        _ = try SQLBlock(steps: [.copy(.init(target: table, direction: .from, data: ByteString([])))])
        _ = try SQLBlock(steps: [.copy(.init(target: table, direction: .to))])
        let query = SelectQuery(projection: [.expression(.int(1))], source: .values([]))
        for command in [SQLCopyCommand(target: table, direction: .from),
                        .init(target: table, direction: .to, data: ByteString([])),
                        .init(target: .query(query), direction: .from, data: ByteString([]))] {
            #expect(throws: QueryStructuralValidationError.invalidSQLControl) { try SQLBlock(steps: [.copy(command)]) }
        }
    }

    @Test("New names and COPY input consume one cumulative retained-byte ledger")
    func cumulativeBytes() throws {
        let block = try SQLBlock(steps: [.execute(.init(name: "p")), .deallocate("p"),
            .copy(.init(target: .table(TableRef("t"), columns: ["c"]), direction: .from, data: ByteString([65, 10])))],
            limits: .init(maximumRetainedBytes: 11))
        try QueryStructuralValidator.validate(block, limits: .init(maximumRetainedBytes: 11))
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumRetainedBytes: 10))
        }
    }

    @Test("PREPARE definitions remain independent while caller expressions are bound")
    func independentParameters() throws {
        let body = statement(.parameter(position: 2))
        let block = try SQLBlock(steps: [.prepare(.init(name: "p", parameterTypes: [.integer, .integer], statement: body)),
            .execute(.init(name: "p", arguments: [.parameter(position: 1)])),
            .setting(.set(name: .statementTimeout, value: .parameter(position: 1), scope: .local)),
            .explain(.init(statement: statement(.parameter(position: 1))))])
        let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
        let strings = [QueryParameter(position: 1, value: .primitive(.string("1234")))]
        let repeated = try SQLBlock(steps: [.execute(.init(name: "p", arguments: [.parameter(position: 1)])),
            .execute(.init(name: "p", arguments: [.parameter(position: 1)]))])
        let exact = try QueryParameterBinder(parameters: strings, structuralLimits: .init(maximumRetainedBytes: 10))
        try exact.validate(repeated)
        _ = try exact.bind(repeated)
        let tight = try QueryParameterBinder(parameters: strings, structuralLimits: .init(maximumRetainedBytes: 9))
        #expect(throws: QueryParameterBindingError.self) { try tight.validate(repeated) }
        #expect(throws: QueryParameterBindingError.self) { try tight.bind(repeated) }
        let bound = try binder.bind(block)
        #expect(bound.steps[0] == block.steps[0])
        #expect(bound.steps[1] == .execute(.init(name: "p", arguments: [.int(7)])))
        #expect(bound.steps[2] == .setting(.set(name: .statementTimeout, value: .int(7), scope: .local)))
        #expect(bound.steps[3] == .explain(.init(statement: statement(.int(7)))))
        try binder.validate(block)
        #expect(throws: QueryParameterBindingError.missingPosition(3)) {
            try binder.bind(SQLBlock(steps: [.execute(.init(name: "p", arguments: [.parameter(position: 3)]))]))
        }
    }

    @Test("Deep prepared types use iterative identity and structural admission")
    func deepDefinitions() throws {
        let named = try SQLBlock(steps: [.prepare(.init(name: "p", parameterTypes: [.array(.custom("t", schema: "é"))],
            statement: statement()))], limits: .init(maximumRetainedBytes: 4))
        try QueryStructuralValidator.validate(named, limits: .init(maximumRetainedBytes: 4))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(resource: .retainedBytes, actual: 4, maximum: 3)) {
            try QueryStructuralValidator.validate(named, limits: .init(maximumRetainedBytes: 3))
        }
        var type = DataType.integer
        for _ in 0..<300 { type = .array(type) }
        let step = SQLBlockStep.prepare(.init(name: "p", parameterTypes: [type], statement: statement()))
        let block = try SQLBlock(steps: [step], limits: .init(maximumNestingDepth: 400))
        #expect(step == block.steps[0]); #expect(Set([step, block.steps[0]]).count == 1)
        #expect(throws: QueryStructuralValidationError.self) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumNestingDepth: 300))
        }
    }

    @Test("COPY reports its direct row count and other operational commands do not")
    func commandMetadata() {
        #expect(SQLCommandKind.copy.reportsAffectedRows)
        for kind: SQLCommandKind in [.begin, .commit, .rollback, .set, .show, .reset, .prepare, .execute, .deallocate, .explain] {
            #expect(!kind.reportsAffectedRows)
        }
    }
}
