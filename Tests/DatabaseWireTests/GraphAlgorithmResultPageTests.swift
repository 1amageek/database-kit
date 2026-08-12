import DatabaseTypes
@_spi(DatabaseOperations) @testable import DatabaseWire
import Testing

@Suite("Owner-retaining graph algorithm results")
struct GraphAlgorithmResultPageTests {
    @Test("ranking page retains its frame and materializes scores on demand")
    func rankingPageRetainsFrame() throws {
        let response = GraphAlgorithmOperation.Response.ranking(
            .init(
                scores: [
                    .init(
                        vertex: .identifier("rank-node"),
                        score: 0.75
                    ),
                ],
                iterations: 8,
                convergenceDelta: 0.001,
                progress: .complete
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.graphAlgorithm,
            requestID: 101,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.graphAlgorithm,
            from: frame,
            matching: 101
        )
        guard case .success(.ranking(let page)) = decoded else {
            Issue.record("Expected a ranking page")
            return
        }
        try expectSharedBacking(
            child: #require(page.retainedEncodedScores),
            owner: frame
        )

        #expect(page.scoreCount == 1)
        var iterator = page.makeScoreIterator()
        #expect(
            try iterator.next()
                == GraphAlgorithmOperation.Score(
                    vertex: .identifier("rank-node"),
                    score: 0.75
                )
        )
        #expect(try iterator.next() == nil)

        #expect(
            throws: DatabaseWireError.collectionTooLarge(
                actual: 1,
                maximum: 0
            )
        ) {
            _ = try page.materializedScores(maximumCount: 0)
        }

        let strictLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 4,
            maximumByteStringBytes: 1_024,
            maximumCollectionCount: 10,
            maximumNestingDepth: 10,
            maximumObjectCount: 100
        )
        #expect(
            throws: DatabaseWireError.stringTooLarge(
                actual: 9,
                maximum: 4
            )
        ) {
            _ = try DatabaseWireEncoder(limits: strictLimits).encodeResponse(
                DatabaseOperationCatalog.graphAlgorithm,
                requestID: 101,
                response: GraphAlgorithmOperation.Response.ranking(page)
            )
        }
    }

    @Test("nested cycle terms retain the original response frame")
    func cycleTermsRetainFrame() throws {
        let response = GraphAlgorithmOperation.Response.cycles(
            .init(
                cycles: [
                    .init(terms: [
                        .identifier("a"),
                        .identifier("b"),
                        .identifier("a"),
                    ]),
                ],
                backEdges: [
                    .init(
                        source: .identifier("b"),
                        target: .identifier("a")
                    ),
                ],
                nodesExplored: 2,
                progress: .complete
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.graphAlgorithm,
            requestID: 102,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.graphAlgorithm,
            from: frame,
            matching: 102
        )
        guard case .success(.cycles(let page)) = decoded else {
            Issue.record("Expected a cycle page")
            return
        }
        try expectSharedBacking(
            child: #require(page.retainedEncodedCycles),
            owner: frame
        )
        var cycles = page.makeCycleIterator()
        let nextCycle = try cycles.next()
        let cycle = try #require(nextCycle)
        try expectSharedBacking(
            child: #require(cycle.retainedEncodedTerms),
            owner: frame
        )
        #expect(
            try cycle.materializedTerms(maximumCount: 3)
                == [
                    .identifier("a"),
                    .identifier("b"),
                    .identifier("a"),
                ]
        )
    }

    @Test("invalid score terms are rejected before iteration")
    func invalidScoreTermIsRejectedDuringAcceptance() throws {
        let response = GraphAlgorithmOperation.Response.ranking(
            .init(
                scores: [
                    .init(
                        vertex: .identifier("unique-rank-node"),
                        score: 1
                    ),
                ],
                iterations: 1,
                convergenceDelta: 0,
                progress: .complete
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.graphAlgorithm,
            requestID: 103,
            response: response
        )
        var corrupted = Array(frame)
        let marker = Array("unique-rank-node".utf8)
        let markerIndex = try #require(firstIndex(of: marker, in: corrupted))
        #expect(corrupted[markerIndex - 5] == 1)
        corrupted[markerIndex - 5] = 0xFF

        #expect(throws: DatabaseWireError.invalidValueTag(0xFF)) {
            _ = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.graphAlgorithm,
                from: ByteString(corrupted),
                matching: 103
            )
        }
    }

    private func expectSharedBacking(
        child: ByteString,
        owner: ByteString
    ) throws {
        let ownerRange = try #require(
            owner.withUnsafeBytes { bytes -> Range<UInt>? in
                guard let baseAddress = bytes.baseAddress else {
                    return nil
                }
                let start = UInt(bitPattern: baseAddress)
                return start..<(start + UInt(bytes.count))
            }
        )
        let childAddress = try #require(
            child.withUnsafeBytes { bytes in
                bytes.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        #expect(ownerRange.contains(childAddress))
    }

    private func firstIndex(
        of pattern: [UInt8],
        in bytes: [UInt8]
    ) -> Int? {
        guard pattern.count <= bytes.count else {
            return nil
        }
        for index in 0...(bytes.count - pattern.count) {
            if bytes[index..<(index + pattern.count)]
                .elementsEqual(pattern) {
                return index
            }
        }
        return nil
    }
}
