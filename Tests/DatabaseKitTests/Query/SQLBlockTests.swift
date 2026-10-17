import DatabaseKit
import Testing

@Suite("SQL block semantic admission")
struct SQLBlockTests {
    @Test("Blocks retain ordered statement values and independent immutable storage")
    func preservesOrderedSteps() throws {
        let statement = select()
        var steps: [SQLBlockStep] = [
            .statement(statement), .savepoint("point"),
            .rollbackTo("point"), .release("point"), .statement(statement)
        ]
        let block = try SQLBlock(steps: steps)
        steps.removeAll()
        #expect(block.steps == [
            .statement(statement), .savepoint("point"),
            .rollbackTo("point"), .release("point"), .statement(statement)
        ])
        #expect(block == (try SQLBlock(steps: block.steps)))
    }

    @Test("An empty block is an explicit structural failure")
    func rejectsEmptyBlock() {
        #expect(throws: QueryStructuralValidationError.emptySQLBlock) {
            _ = try SQLBlock(steps: [])
        }
    }

    @Test("Every checkpoint transition rejects empty and NUL names")
    func rejectsInvalidCheckpointNames() {
        for name in ["", "before\0after"] {
            for step in [SQLBlockStep.savepoint(name), .rollbackTo(name), .release(name)] {
                #expect(throws: QueryStructuralValidationError.invalidSQLCheckpointName) {
                    _ = try SQLBlock(steps: [step])
                }
            }
        }
    }

    @Test("Checkpoint identity preserves UTF8 spelling and transition kind")
    func preservesExactCheckpointIdentity() throws {
        let composed = "\u{00e9}"
        let decomposed = "e\u{0301}"
        #expect(composed == decomposed)
        let pairs: [(SQLBlockStep, SQLBlockStep)] = [
            (SQLBlockStep.savepoint(composed), .savepoint(decomposed)),
            (.rollbackTo(composed), .rollbackTo(decomposed)),
            (.release(composed), .release(decomposed))
        ]
        for pair in pairs {
            #expect(pair.0 != pair.1)
            #expect(Set([pair.0, pair.1, pair.0]).count == 2)
        }
        #expect(Set([SQLBlockStep.savepoint("same"), .rollbackTo("same"), .release("same")]).count == 3)
        let block = try SQLBlock(steps: [.savepoint(composed), .savepoint(decomposed), .savepoint(composed)])
        #expect(block.steps.count == 3)
    }

    @Test("Block steps and contained statement collections share exact admission")
    func cumulativeCollectionBoundary() throws {
        let block = try SQLBlock(steps: [.statement(select()), .statement(select())])
        try QueryStructuralValidator.validate(block, limits: .init(maximumCollectionElements: 4))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .collectionElements, actual: 4, maximum: 3
        )) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumCollectionElements: 3))
        }
    }

    @Test("Contained statements do not reset the cumulative node ledger")
    func cumulativeNodeBoundary() throws {
        let block = try SQLBlock(steps: [.statement(select()), .statement(select())])
        try QueryStructuralValidator.validate(block, limits: .init(maximumTotalNodes: 9))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .totalNodes, actual: 9, maximum: 8
        )) {
            try QueryStructuralValidator.validate(block, limits: .init(maximumTotalNodes: 8))
        }
    }

    @Test("Checkpoint UTF8 byte admission is cumulative across transition kinds")
    func cumulativeCheckpointByteBoundary() throws {
        let block = try SQLBlock(steps: [.savepoint("\u{00e9}"), .release("s")],
            limits: .init(maximumRetainedBytes: 3))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .retainedBytes, actual: 3, maximum: 2
        )) {
            _ = try SQLBlock(steps: block.steps, limits: .init(maximumRetainedBytes: 2))
        }
    }

    @Test("Supplied parameters share block collection and name byte admission")
    func cumulativeParameterBoundary() throws {
        let block = try SQLBlock(steps: [.savepoint("aa")])
        let parameters = [QueryParameter(position: 1, name: "b", value: .primitive(.null))]
        try QueryStructuralValidator.validate(block, parameters: parameters,
            limits: .init(maximumRetainedBytes: 3, maximumCollectionElements: 2))
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .retainedBytes, actual: 3, maximum: 2
        )) {
            try QueryStructuralValidator.validate(block, parameters: parameters,
                limits: .init(maximumRetainedBytes: 2))
        }
        #expect(throws: QueryStructuralValidationError.resourceLimitExceeded(
            resource: .collectionElements, actual: 2, maximum: 1
        )) {
            try QueryStructuralValidator.validate(block, parameters: parameters,
                limits: .init(maximumCollectionElements: 1))
        }
    }

    @Test("Block construction validates the real contained statement shape")
    func rejectsInvalidContainedStatement() {
        let query = SelectQuery(
            projection: [ProjectionItem(.arrayAccess(.null, subscripts: []))],
            source: .values([])
        )
        #expect(throws: QueryStructuralValidationError.invalidArrayAccessSubscriptCount(0)) {
            _ = try SQLBlock(steps: [.savepoint("point"), .statement(.select(query))])
        }
    }

    @Test("Mutation command metadata requires row counts and checkpoints do not")
    func commandAffectedRowMeaning() {
        for kind in [SQLCommandKind.insert, .update, .delete] {
            #expect(kind.reportsAffectedRows)
        }
        for kind in [SQLCommandKind.savepoint, .rollbackTo, .release] {
            #expect(!kind.reportsAffectedRows)
        }
    }

    private func select() -> QueryStatement {
        .select(SelectQuery(projection: [.wildcard()], source: .values([])))
    }
}
