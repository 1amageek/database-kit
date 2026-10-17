import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import DatabaseKit
import Testing

@Suite("Relational query Wire carriage")
struct RelationalQueryWireTests {
    @Test("SELECT has one ordered projection and canonical field order")
    func minimalSelectGolden() throws {
        let query = identityQuery()
        let bytes = try QueryIRWireFormat.encode(.select(query))
        let expected: [UInt8] = [
            0, // Statement SELECT.
            0, // No CTEs.
            1, 0, 0, 0, 1, 0, // One unqualified wildcard.
            14, 1, 0, 0, 0, 0, 0, 0, 0, // One zero-column VALUES row.
            0, 0, 0, 0, // Access path, filter, grouping, having absent.
            0, 0, 0, 0, // No named windows.
            0, 0, // ALL, no ordering.
            0, 0, // Offset and limit absent.
            0, 0, // Reduced and implicit dataset.
            0, // WITH RECURSIVE absent.
        ]
        #expect(bytes == ByteString(expected))
        #expect(try QueryIRWireFormat.decode(bytes) == .select(query))
    }

    @Test("Projection, quantifiers, counts, CTE hints and optional emptiness survive carriage")
    func completeEnvelopeRoundTrips() throws {
        let counts: [QueryCount] = [.fixed(0), .fixed(UInt64.max), .expression(.parameter(.position(1)))]
        let quantifiers: [SelectQuantifier] = [.all, .distinct, .distinctOn([.col("x"), .parameter(.name("key"))])]
        for count in counts {
            for quantifier in quantifiers {
                for limit: QueryLimit? in [nil, .all, .count(count, withTies: false), .count(count, withTies: true)] {
                    let query = SelectQuery(
                        projection: [.wildcard(), .expression(.wholeRow("r"), alias: "row"), .wildcard(qualifier: "r")],
                        source: .aliased(.values([[.parameter(.name("x"))]]), name: "r", columns: []),
                        groupBy: [], orderBy: [], quantifier: quantifier,
                        pagination: QueryPagination(limit: limit, offset: count),
                        subqueries: [NamedSubquery(name: "first", columns: [], query: identityQuery(), materialized: .materialized),
                                     NamedSubquery(name: "second", query: identityQuery(), materialized: .notMaterialized)]
                    )
                    try expectRoundTrip(query)
                }
            }
        }
        let query = SelectQuery(projection: [], source: .values([]), quantifier: .distinctOn([.wholeRow("r")]),
            pagination: QueryPagination(limit: .count(.fixed(UInt64.max), withTies: true), offset: .fixed(UInt64.max)))
        let golden: [UInt8] = [0, 0, 0, 0, 0, 0, 14, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 2, 1, 0, 0, 0, 58, 1, 0, 0, 0, 114, 0, 1, 0]
            + Array(repeating: 255, count: 8) + [1, 1, 1, 0]
            + Array(repeating: 255, count: 8) + [0, 0, 0]
        #expect(try QueryIRWireFormat.encode(.select(query)) == ByteString(golden))

    }

    @Test("New source discriminators carry expression VALUES, bare subqueries, aliases and binary queries")
    func sourceTagsAndBinaryModifiers() throws {
        let identityBytes = Array(try QueryIRWireFormat.encode(.select(identityQuery()))).dropFirst()
        let sourceGoldens: [(DataSource, [UInt8])] = [
            (.values([]), [14, 0, 0, 0, 0]),
            (.values([[.wholeRow("r")]]), [14, 1, 0, 0, 0, 1, 0, 0, 0, 58, 1, 0, 0, 0, 114]),
            (.subquery(identityQuery()), [15] + identityBytes),
            (.aliased(.values([]), name: "r"), [16, 1, 0, 0, 0, 114, 0, 14, 0, 0, 0, 0]),
            (.aliased(.values([]), name: "r", columns: []), [16, 1, 0, 0, 0, 114, 1, 0, 0, 0, 0, 14, 0, 0, 0, 0]),
        ]
        for (source, golden) in sourceGoldens { #expect(try encodeSource(source) == ByteString(golden)) }
        for (operation, byte): (SetOperator, UInt8) in [(.union, 0), (.intersect, 1), (.except, 2)] {
            for (quantifier, quantifierByte): (SetQuantifier, UInt8) in [(.all, 0), (.distinct, 1)] {
                let query = SelectQuery(projection: [.wildcard()], source: .setOperation(
                    operator: operation, quantifier: quantifier, left: identityQuery(), right: identityQuery()))
                let expected = [UInt8(0), 0, 1, 0, 0, 0, 1, 0, 17, byte, quantifierByte]
                    + identityBytes + identityBytes + Array(repeating: UInt8(0), count: 15)
                #expect(try QueryIRWireFormat.encode(.select(query)) == ByteString(expected))
            }
        }
        let left = identityQuery().replacing(pagination: QueryPagination(limit: .count(.fixed(1), withTies: false)))
        let right = identityQuery().replacing(orderBy: [SortKey(.int(9))])
        let sources: [(DataSource, UInt8)] = [
            (.values([[.parameter(.position(1)), .int(2)], [.int(3), .parameter(.name("x"))]]), 14),
            (.subquery(left), 15),
            (.aliased(.subquery(right), name: "r", columns: ["a", "b"]), 16),
        ]
        for (source, tag) in sources {
            let bytes = try encodeSource(source)
            #expect(bytes[0] == tag)
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRWireFormat.decodeDataSource(from: &reader) == source)
            try reader.ensureFullyRead()
        }
        for operation: SetOperator in [.union, .intersect, .except] {
            for quantifier: SetQuantifier in [.all, .distinct] {
                let query = SelectQuery(projection: [.wildcard()], source: .setOperation(
                    operator: operation, quantifier: quantifier, left: left, right: right),
                    orderBy: [SortKey(.int(2))], pagination: QueryPagination(limit: .all), subqueries: [])
                try expectRoundTrip(query)
            }
        }
    }

    @Test("New expression discriminators preserve exact metadata and iterative children")
    func expressionGoldens() throws {
        let cases: [(Expression, [UInt8])] = [
            (.wholeRow("r"), [58, 1, 0, 0, 0, 114]),
            (.collate(.wholeRow("r"), collation: .c), [56, 0, 58, 1, 0, 0, 0, 114]),
            (.collate(.wholeRow("r"), collation: .posix), [56, 1, 58, 1, 0, 0, 0, 114]),
            (.field(.wholeRow("r"), name: "f"), [59, 1, 0, 0, 0, 102, 58, 1, 0, 0, 0, 114]),
            (.fieldExpansion(.wholeRow("r")), [60, 58, 1, 0, 0, 0, 114]),
        ]
        for (expression, golden) in cases {
            let bytes = try encodeExpression(expression)
            #expect(bytes == ByteString(golden))
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRWireFormat.decodeExpression(from: &reader) == expression)
            try reader.ensureFullyRead()
        }
        let arrayQuery = Expression.arraySubquery(identityQuery())
        #expect(try encodeExpression(arrayQuery)[0] == 57)
        try expectRoundTrip(identityQuery().replacing(projection: [.expression(arrayQuery)]))
    }

    @Test("Reserved source and unknown metadata bytes fail explicitly")
    func reservedTagsAreRejected() throws {
        var tags: [UInt8] = [2, 4, 9, 10, 11, 12, 19, 255]
        #if !DATABASE_KIT_MULTI_BASE
        tags.append(13)
        #endif
        for tag in tags {
            #expect(throws: DatabaseWireError.invalidValueTag(tag)) {
                var reader = DatabaseWireReader([tag])
                _ = try QueryIRWireFormat.decodeDataSource(from: &reader)
            }
        }
        for bytes: [UInt8] in [[56, 2], [17, 3], [17, 0, 2]] {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(bytes)
                if bytes[0] == 56 { _ = try QueryIRWireFormat.decodeExpression(from: &reader) }
                else { _ = try QueryIRWireFormat.decodeDataSource(from: &reader) }
            }
        }
    }

    @Test("Intrinsic shape errors preserve their typed cause before streaming emits")
    func invalidShapesRejectBeforeEmission() throws {
        let set = DataSource.setOperation(operator: .union, quantifier: .all, left: identityQuery(), right: identityQuery())
        let cases: [(SelectQuery, QueryStructuralValidationError)] = [
            (SelectQuery(projection: [.wildcard()], source: .values([[], [.int(1)]])), .invalidValuesRowArity(row: 1, expected: 0, actual: 1)),
            (identityQuery().replacing(quantifier: .distinctOn([])), .emptyDistinctOn),
            (SelectQuery(projection: [.expression(.int(1))], source: set), .invalidSetQueryEnvelope),
            (SelectQuery(projection: [.wildcard()], source: .aliased(set, name: "r")), .invalidSetQueryEnvelope),
            (SelectQuery(projection: [.wildcard()], source: .table(TableRef(table: "t", alias: "r"))), .sourceAliasInTableReference),
        ]
        for (query, cause) in cases {
            #expect(throws: DatabaseWireError.invalidQueryStructure(cause)) { try QueryIRWireFormat.encode(.select(query)) }
            var prepared = false
            var emitted = false
            #expect(throws: DatabaseWireEmissionError<Never>.encoding(.invalidQueryStructure(cause))) {
                try QueryIRWireFormat.emitCanonicalEncoding(.select(query), prepare: { _ in prepared = true }, consume: { _ in emitted = true })
            }
            #expect(!prepared && !emitted)
        }
        let raggedBytes = [UInt8(14), 2, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0]
            + Array(try encodeExpression(.int(1)))
        var ragged = DatabaseWireReader(ByteString(raggedBytes))
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidValuesRowArity(row: 1, expected: 0, actual: 1))) {
            try QueryIRWireFormat.decodeDataSource(from: &ragged)
        }
        #expect(ragged.currentNestingDepth == 0)
        var emptyDistinct = Array(try QueryIRWireFormat.encode(.select(identityQuery())))
        // The quantifier follows the four-byte named-window count at offsets 21...24.
        emptyDistinct.replaceSubrange(25..<26, with: [2, 0, 0, 0, 0])
        #expect(throws: DatabaseWireError.invalidQueryStructure(.emptyDistinctOn)) {
            try QueryIRWireFormat.decode(ByteString(emptyDistinct))
        }
        var invalidEnvelope = Array(try QueryIRWireFormat.encode(.select(SelectQuery(projection: [.wildcard()], source: set))))
        invalidEnvelope.replaceSubrange(6..<8, with: [0, 58, 1, 0, 0, 0, 114, 0])
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidSetQueryEnvelope)) {
            try QueryIRWireFormat.decode(ByteString(invalidEnvelope))
        }
        var invalidBool = Array(try QueryIRWireFormat.encode(.select(identityQuery())))
        invalidBool[7] = 2
        #expect(throws: DatabaseWireError.invalidBool(2)) { try QueryIRWireFormat.decode(ByteString(invalidBool)) }

    }

    @Test("VALUES expansion preserves raw cells and defers only direct expanded arity")
    func valuesExpansionDefersArity() throws {
        let expansion = Expression.fieldExpansion(.row([.int(1), .int(2)]))
        let admittedRows: [[[Expression]]] = [
            [[expansion], [.int(3), .int(4)]],
            [[.int(3), .int(4)], [expansion]],
            [[.int(3)], [.int(4), .int(5)], [expansion]],
            // This carriage is valid; the runtime binder rejects its expanded width mismatch.
            [[expansion], [.int(3)]],
        ]
        for rows in admittedRows {
            let source = DataSource.values(rows)
            let query = SelectQuery(projection: [.wildcard()], source: source)
            try expectRoundTrip(query)
            var reader = DatabaseWireReader(try encodeSource(source))
            #expect(try QueryIRWireFormat.decodeDataSource(from: &reader) == source)
            try reader.ensureFullyRead()
        }
        let nested = Expression.row([expansion])
        let cause = QueryStructuralValidationError.invalidValuesRowArity(row: 1, expected: 1, actual: 2)
        #expect(throws: DatabaseWireError.invalidQueryStructure(cause)) {
            try encodeSource(.values([[nested], [.int(3), .int(4)]]))
        }
        let malformed = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(14)
            try writer.writeCount(2)
            try writer.writeCount(1)
            try QueryIRWireFormat.encodeExpression(nested, into: &writer)
            try writer.writeCount(2)
            try QueryIRWireFormat.encodeExpression(.int(3), into: &writer)
            try QueryIRWireFormat.encodeExpression(.int(4), into: &writer)
        }
        var reader = DatabaseWireReader(malformed)
        #expect(throws: DatabaseWireError.invalidQueryStructure(cause)) {
            try QueryIRWireFormat.decodeDataSource(from: &reader)
        }
        #expect(reader.currentNestingDepth == 0)
    }

    @Test("Every truncated mixed-query prefix and trailing bytes fail")
    func everyPrefixAndTrailingBytesFail() throws {
        let query = SelectQuery(projection: [.wildcard(qualifier: "r"), .expression(.arraySubquery(identityQuery()))],
            source: .aliased(.values([[.fieldExpansion(.wholeRow("r"))]]), name: "r", columns: ["f"]),
            quantifier: .distinctOn([.collate(.col("f"), collation: .posix)]),
            pagination: QueryPagination(limit: .count(.expression(.parameter(.name("n"))), withTies: true), offset: .fixed(UInt64.max)),
            subqueries: [NamedSubquery(name: "c", query: identityQuery(), materialized: .notMaterialized)])
        let bytes = try QueryIRWireFormat.encode(.select(query))
        for end in 0..<bytes.count {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(bytes[0..<end]) }
        }
        #expect(throws: DatabaseWireError.trailingBytes) { try QueryIRWireFormat.decode(ByteString(Array(bytes) + [0])) }
        try expectRoundTrip(query)
    }

    @Test("Deep alternating new children use shared depth limits")
    func deepMixedChildrenAreBounded() throws {
        var expression: Expression = .wholeRow("r")
        for _ in 0..<120 {
            expression = .collate(.field(.fieldExpansion(expression), name: "f"), collation: .c)
        }
        let query = identityQuery().replacing(projection: [.expression(expression)])
        let limits = try wireLimits(depth: 512)
        let bytes = try QueryIRWireFormat.encode(.select(query), limits: limits)
        #expect(try QueryIRWireFormat.decode(bytes, limits: limits) == .select(query))
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(.select(query)) }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(bytes) }
    }

    @Test("Row counts and frame limits are admitted before children")
    func collectionAndFrameBoundaries() throws {
        let query = SelectQuery(projection: [.wildcard()], source: .values([[.int(1)], [.int(2)]]))
        let bytes = try QueryIRWireFormat.encode(.select(query))
        let exact = try wireLimits(frame: bytes.count)
        #expect(try QueryIRWireFormat.encode(.select(query), limits: exact) == bytes)
        #expect(try QueryIRWireFormat.decode(bytes, limits: exact) == .select(query))
        let short = try wireLimits(frame: bytes.count - 1)
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(.select(query), limits: short) }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(bytes, limits: short) }
        let one = try wireLimits(collection: 1)
        #expect(throws: DatabaseWireError.collectionTooLarge(actual: 2, maximum: 1)) { try QueryIRWireFormat.encode(.select(query), limits: one) }
        #expect(throws: DatabaseWireError.collectionTooLarge(actual: 2, maximum: 1)) { try QueryIRWireFormat.decode(bytes, limits: one) }
    }

    @Test("Mutation table aliases retain their direct TableRef contract")
    func mutationTargetAliasSurvives() throws {
        let target = TableRef(schema: "s", table: "t", alias: "r")
        let statement = QueryStatement.delete(DeleteQuery(target: target, returning: [.wildcard()]))
        #expect(try QueryIRWireFormat.decode(QueryIRWireFormat.encode(statement)) == statement)
    }

    private func identityQuery() -> SelectQuery { SelectQuery(projection: [.wildcard()], source: .values([[]])) }

    private func expectRoundTrip(_ query: SelectQuery) throws {
        let statement = QueryStatement.select(query)
        let bytes = try QueryIRWireFormat.encode(statement)
        #expect(try QueryIRWireFormat.decode(bytes) == statement)
        var streamed: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(statement, prepare: { #expect($0 == bytes.count) }, consume: { streamed.append(contentsOf: $0) })
        #expect(ByteString(streamed) == bytes)
    }

    private func encodeSource(_ source: DataSource) throws -> ByteString {
        try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeDataSource(source, into: &writer)
        }
    }

    private func encodeExpression(_ value: Expression) throws -> ByteString {
        try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(value, into: &writer)
        }
    }

    private func wireLimits(frame: Int = 1_048_576, collection: Int = 10_000, depth: Int = 64) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: 1_024, maximumByteStringBytes: 1_024,
            maximumCollectionCount: collection, maximumNestingDepth: depth, maximumObjectCount: 100_000)
    }
}
