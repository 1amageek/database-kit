import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import DatabaseKit
import Testing

@Suite("QueryIR streaming wire")
struct QueryIRStreamingWireTests {
    @Test("streaming output exactly matches owned canonical encoding")
    func streamingMatchesOwnedEncoding() throws {
        let statement = canonicalStatement()
        let expected = try QueryIRWireFormat.encode(statement)
        var preparedByteCount: Int?
        var streamed: [UInt8] = []

        try QueryIRWireFormat.emitCanonicalEncoding(
            statement,
            prepare: { byteCount in
                preparedByteCount = byteCount
                streamed.reserveCapacity(byteCount)
            },
            consume: { bytes in
                streamed.append(contentsOf: bytes)
            }
        )

        #expect(preparedByteCount == expected.count)
        #expect(ByteString(streamed) == expected)
    }

    @Test("prepare failure occurs before the first sink emission")
    func prepareFailurePreventsEmission() throws {
        let statement = canonicalStatement()
        let expectedByteCount = try QueryIRWireFormat.encode(statement).count
        var preparedByteCount: Int?
        var emittedByteCount = 0

        #expect(
            throws: DatabaseWireEmissionError<DatabaseWireError>.destination(
                .byteCountOverflow
            )
        ) {
            try QueryIRWireFormat.emitCanonicalEncoding(
                statement,
                prepare: { (byteCount: Int) throws(DatabaseWireError) in
                    preparedByteCount = byteCount
                    throw DatabaseWireError.byteCountOverflow
                },
                consume: { bytes in
                    emittedByteCount += bytes.count
                }
            )
        }

        #expect(preparedByteCount == expectedByteCount)
        #expect(emittedByteCount == 0)
    }

    @Test("frame rejection occurs before prepare and sink emission")
    func frameRejectionPreventsEmission() throws {
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 1,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 1_024,
            maximumCollectionCount: 1_024,
            maximumNestingDepth: 64,
            maximumObjectCount: 4_096
        )
        var prepareCallCount = 0
        var emittedByteCount = 0

        #expect {
            try QueryIRWireFormat.emitCanonicalEncoding(
                canonicalStatement(),
                limits: limits,
                prepare: { _ in
                    prepareCallCount += 1
                },
                consume: { bytes in
                    emittedByteCount += bytes.count
                }
            )
        } throws: { error in
            guard case DatabaseWireEmissionError<Never>.encoding(
                .frameTooLarge(let actual, let maximum)
            ) = error else {
                return false
            }
            return actual > maximum && maximum == 1
        }

        #expect(prepareCallCount == 0)
        #expect(emittedByteCount == 0)
    }

    @Test("deep QueryIR streams without process-stack recursion")
    func deepQueryEncodingSupportsConfiguredDepth() throws {
        var expression: Expression = .bool(true)
        for _ in 0..<320 {
            expression = .not(expression)
        }
        let statement = QueryStatement.select(SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "events")),
            filter: expression
        ))
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024 * 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 1_024,
            maximumCollectionCount: 4_096,
            maximumNestingDepth: 512,
            maximumObjectCount: 100_000
        )
        let expected = try QueryIRWireFormat.encode(statement, limits: limits)
        var streamed: [UInt8] = []

        try QueryIRWireFormat.emitCanonicalEncoding(
            statement,
            limits: limits,
            prepare: { streamed.reserveCapacity($0) },
            consume: { streamed.append(contentsOf: $0) }
        )

        #expect(ByteString(streamed) == expected)
    }

    private func canonicalStatement() -> QueryStatement {
        .select(SelectQuery(
            projection: .items([
                ProjectionItem(.variable(Variable("event"))),
            ]),
            source: .graphPattern(.basic([
                TriplePattern(
                    subject: .variable("event"),
                    predicate: .iri("urn:calendar:title"),
                    object: .literal(.string("Festival"))
                ),
            ])),
            orderBy: [SortKey(.variable(Variable("event")))],
            limit: 20
        ))
    }
}
