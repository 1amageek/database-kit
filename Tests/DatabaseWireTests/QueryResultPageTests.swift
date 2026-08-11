import DatabaseKit
import DatabaseTypes
@_spi(DatabaseWireRuntime) @testable import DatabaseWire
import Testing

@Suite("Owner-retaining query result pages")
struct QueryResultPageTests {
    @Test("row page retains one frame range and materializes rows on demand")
    func rowPageRetainsFrameRange() throws {
        let response = QueryExecuteOperation.Response.rows(
            try QueryRowPage(
                columns: [
                    QueryColumn(number: 1, name: "payload"),
                ],
                rows: [
                    QueryRow(values: [.bytes([1, 2, 3, 4])]),
                    QueryRow(values: [.bytes([5, 6, 7, 8])]),
                ],
                continuation: [9, 10],
                provenance: nil,
                consistency: try consistency(version: 21)
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.queryExecute,
            requestID: 91,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperations.queryExecute,
            from: frame,
            matching: 91
        )
        guard case .success(.rows(let page)) = decoded else {
            Issue.record("Expected a row page")
            return
        }
        let encodedRows = try #require(page.retainedEncodedRows)
        try expectSharedBacking(child: encodedRows, owner: frame)

        #expect(page.rowCount == 2)
        #expect(page.columns == [QueryColumn(number: 1, name: "payload")])
        var iterator = page.makeRowIterator()
        let firstRow = try iterator.next()
        let first = try #require(firstRow)
        guard let firstValue = first.values.first,
              case .bytes(let firstPayload) = firstValue else {
            Issue.record("Expected a borrowed byte field")
            return
        }
        try expectSharedBacking(child: firstPayload, owner: frame)
        #expect(try iterator.next()?.values == [.bytes([5, 6, 7, 8])])
        #expect(try iterator.next() == nil)
    }

    @Test("RDF page retains one frame range and materializes quads on demand")
    func rdfPageRetainsFrameRange() throws {
        let quad = RDFQuad(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: RDFPredicateIRI(try RDFIRI("urn:predicate")),
            object: .literal(
                RDFLiteral(
                    lexicalForm: "value",
                    annotation: .typed(
                        XSDDatatype.string.typedLiteralDatatype
                    )
                )
            )
        )
        let response = QueryExecuteOperation.Response.rdfGraph(
            try RDFGraphPage(
                quads: [quad, quad],
                continuation: [1],
                provenance: nil,
                consistency: try consistency(version: 34)
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.queryExecute,
            requestID: 92,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperations.queryExecute,
            from: frame,
            matching: 92
        )
        guard case .success(.rdfGraph(let page)) = decoded else {
            Issue.record("Expected an RDF graph page")
            return
        }
        let encodedQuads = try #require(page.retainedEncodedQuads)
        try expectSharedBacking(child: encodedQuads, owner: frame)

        #expect(page.quadCount == 2)
        var iterator = page.makeQuadIterator()
        #expect(try iterator.next() == quad)
        #expect(try iterator.next() == quad)
        #expect(try iterator.next() == nil)
    }

    @Test("row structural failures are rejected before iteration")
    func rowPageRejectsInvalidValueTagDuringAcceptance() throws {
        let response = QueryExecuteOperation.Response.rows(
            try QueryRowPage(
                columns: [QueryColumn(number: 1, name: "marker")],
                rows: [
                    QueryRow(values: [.uint64(0x8877_6655_4433_2211)]),
                ],
                continuation: nil,
                provenance: nil,
                consistency: try consistency()
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.queryExecute,
            requestID: 93,
            response: response
        )
        var corrupted = Array(frame)
        let marker: [UInt8] = [
            0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        ]
        let payloadIndex = try #require(firstIndex(of: marker, in: corrupted))
        #expect(corrupted[payloadIndex - 1] == 9)
        corrupted[payloadIndex - 1] = 0xFF

        #expect(throws: DatabaseWireError.invalidValueTag(0xFF)) {
            _ = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperations.queryExecute,
                from: ByteString(corrupted),
                matching: 93
            )
        }
    }

    @Test("materialization requires an explicit independent limit")
    func materializationLimit() throws {
        let page = try QueryRowPage(
            columns: [],
            rows: [QueryRow(values: []), QueryRow(values: [])],
            continuation: nil,
            provenance: nil,
            consistency: try consistency()
        )

        #expect(
            throws: DatabaseWireError.collectionTooLarge(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try page.materializedRows(maximumCount: 1)
        }
    }

    @Test("retained rows cannot bypass stricter encoding limits")
    func retainedRowsRespectSelectedEncodingLimits() throws {
        let response = QueryExecuteOperation.Response.rows(
            try QueryRowPage(
                columns: [QueryColumn(number: 1, name: "v")],
                rows: [QueryRow(values: [.string("long value")])],
                continuation: nil,
                provenance: nil,
                consistency: try consistency()
            )
        )
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperations.queryExecute,
            requestID: 94,
            response: response
        )
        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperations.queryExecute,
            from: frame,
            matching: 94
        )
        guard case .success(let retainedResponse) = decoded else {
            Issue.record("Expected a retained row response")
            return
        }
        let strictLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 1,
            maximumByteStringBytes: 1_024,
            maximumCollectionCount: 10,
            maximumNestingDepth: 10,
            maximumObjectCount: 100
        )

        #expect(
            throws: DatabaseWireError.stringTooLarge(
                actual: 10,
                maximum: 1
            )
        ) {
            _ = try DatabaseWireEncoder(limits: strictLimits).encodeResponse(
                DatabaseOperations.queryExecute,
                requestID: 94,
                response: retainedResponse
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

    private func consistency(
        version: UInt64 = 1
    ) throws -> DatabaseReadConsistency {
        .transactional(
            try DomainReadPoint(
                domainID: "primary",
                position: .version(version)
            )
        )
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
