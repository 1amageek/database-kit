import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("SQL conditional Wire grammar")
struct SQLConditionalWireTests {
    @Test("New tags have fixed bytes and searched CASE retains tag29")
    func goldenTags() throws {
        #expect(try encode(.caseWhen(cases: [], elseResult: nil)) == ByteString([29, 0, 0, 0, 0, 0]))
        #expect(try encode(.caseWhen(operand: .null, cases: [], elseResult: nil)) == ByteString([44, 0, 0, 0, 0, 0, 0, 0]))
        #expect(try encode(.greatest([])) == ByteString([45, 0, 0, 0, 0]))
        #expect(try encode(.least([])) == ByteString([46, 0, 0, 0, 0]))
        #expect(try encode(.truthTest(.null, value: .unknown, negated: true)) == ByteString([47, 0, 0, 2, 1]))
        #expect(try encode(.isDistinctFrom(.null, .null, negated: false)) == ByteString([48, 0, 0, 0, 0, 0]))
        #expect(try encode(.quantifiedComparison(.null, comparison: .greaterThanOrEqual, quantifier: .all, source: .array(.null)))
            == ByteString([49, 0, 0, 5, 1, 0, 0, 0]))
    }

    @Test("Conditional children and every closed discriminator round trip")
    func discriminatorRoundTrips() throws {
        let comparisons: [ComparisonOperator] = [.equal, .notEqual, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual]
        for comparison in comparisons {
            for quantifier: ComparisonQuantifier in [.any, .all] {
                for source: QuantifiedComparisonSource in [.array(.parameter(.position(2))), .subquery(query(.parameter(.position(3))))] {
                    try roundTrip(.quantifiedComparison(.parameter(.position(1)), comparison: comparison, quantifier: quantifier, source: source))
                }
            }
        }
        for truth: TruthValue in [.false, .true, .unknown] {
            for negated in [false, true] {
                try roundTrip(.truthTest(.null, value: truth, negated: negated))
                try roundTrip(.isDistinctFrom(.int(1), .null, negated: negated))
            }
        }
        for expression in fixtures { try roundTrip(expression) }
    }

    @Test("Every truncated conditional production is rejected")
    func truncatedProductions() throws {
        for expression in fixtures {
            let bytes = try encode(expression)
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) { try decode(ByteString(Array(bytes[0..<end]))) }
            }
        }
    }

    @Test("Unknown truth, comparison, quantifier, source and Boolean bytes fail")
    func malformedDiscriminators() {
        let cases: [(ByteString, DatabaseWireError)] = [
            ([47, 0, 0, 3, 0], .invalidValueTag(3)),
            ([47, 0, 0, 0, 2], .invalidBool(2)),
            ([48, 0, 0, 0, 0, 2], .invalidBool(2)),
            ([49, 0, 0, 6, 0, 0, 0, 0], .invalidValueTag(6)),
            ([49, 0, 0, 0, 2, 0, 0, 0], .invalidValueTag(2)),
            ([49, 0, 0, 0, 0, 2, 0, 0], .invalidValueTag(2)),
            ([52], .invalidValueTag(52)),
        ]
        for (bytes, expected) in cases { #expect(throws: expected) { try decode(bytes) } }
    }

    @Test("Conditional lists obey collection bounds and public decoding rejects trailing bytes")
    func resourceBoundaries() throws {
        let exact = try collectionLimits(2)
        let short = try collectionLimits(1)
        for expression: Expression in [.greatest([.null, .null]), .least([.null, .null]),
            .caseWhen(operand: .null, cases: [CaseWhenPair(condition: .null, result: .null), CaseWhenPair(condition: .null, result: .null)], elseResult: nil)] {
            let bytes = try encode(expression, limits: exact)
            #expect(try decode(bytes, limits: exact) == expression)
            #expect(throws: DatabaseWireError.collectionTooLarge(actual: 2, maximum: 1)) { try encode(expression, limits: short) }
            #expect(throws: DatabaseWireError.collectionTooLarge(actual: 2, maximum: 1)) { try decode(bytes, limits: short) }
        }
        let bytes = try QueryIRWireFormat.encode(.select(query(.truthTest(.null, value: .true, negated: false))))
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString(Array(bytes) + [0])) }
    }

    @Test("New conditional carriage preserves prior exact names and declared typed NULLs")
    func existingSemanticCarriage() throws {
        let expression = Expression.caseWhen(operand: .literal(.sqlUnknownString("Exact")), cases: [CaseWhenPair(
            condition: .function(FunctionCall(name: "Exact.F", arguments: [], schema: "Exact.S")),
            result: .cast(.null, targetType: .custom("Exact.T", schema: "Exact.S")))],
            elseResult: .literal(.queryValue(.primitive(.null), type: .sql(.integer))))
        let statement = QueryStatement.select(query(expression))
        let bytes = try QueryIRWireFormat.encode(statement)
        #expect(try QueryIRWireFormat.decode(bytes) == statement)
        var emitted: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(statement, prepare: { (_: Int) throws(DatabaseWireError) in }, consume: { emitted.append(contentsOf: $0) })
        #expect(ByteString(emitted) == bytes)
        let request = QueryExecuteOperation.Request(input: .ir(statement))
        #if DATABASE_KIT_MULTI_BASE
        let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 51, target: .database, request: request)
        #else
        let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 51, request: request)
        #endif
        #expect(try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame).request == request)
    }

    private var fixtures: [Expression] {
        [.caseWhen(operand: .int(1), cases: [CaseWhenPair(condition: .int(1), result: .int(2))], elseResult: .int(3)),
         .greatest([.int(1), .null]), .least([.null, .int(2)]), .truthTest(.null, value: .unknown, negated: true),
         .isDistinctFrom(.int(1), .null, negated: true),
         .quantifiedComparison(.int(1), comparison: .notEqual, quantifier: .any, source: .array(.parameter(.position(1)))),
         .quantifiedComparison(.int(1), comparison: .lessThan, quantifier: .all, source: .subquery(query(.null)))]
    }

    private func query(_ expression: Expression) -> SelectQuery {
        SelectQuery(projection: .items([ProjectionItem(expression)]), source: .values([], columnNames: nil))
    }

    private func collectionLimits(_ count: Int) throws(DatabaseWireLimitsError) -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: 4096, maximumStringBytes: 1024,
            maximumByteStringBytes: 1024, maximumCollectionCount: count, maximumNestingDepth: 64, maximumObjectCount: 1000)
    }

    private func roundTrip(_ expression: Expression) throws {
        #expect(try decode(encode(expression)) == expression)
    }

    private func encode(_ expression: Expression, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(expression, into: &writer)
        }
    }

    private func decode(_ bytes: ByteString, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> Expression {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let result = try QueryIRWireFormat.decodeExpression(from: &reader)
        try reader.ensureFullyRead()
        return result
    }
}
