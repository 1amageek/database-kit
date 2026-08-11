import DatabaseKit
import DatabaseTypes
@_spi(DatabaseWireRuntime) import DatabaseWire
import Testing

@Suite("Public DatabaseWire boundary")
struct DatabaseWireBoundaryTests {
    private func consistency() throws -> DatabaseReadConsistency {
        .transactional(
            try DomainReadPoint(
                domainID: "primary",
                position: .version(1)
            )
        )
    }

    private let request = QueryExecuteOperation.Request(
        input: .text(
            language: .sparql,
            statement: "ASK { ?subject ?predicate ?object }"
        )
    )

    @Test("encoder and decoder preserve the selected closed operation")
    func requestRoundTrip() throws {
        let encoder = DatabaseWireEncoder()
        let decoder = DatabaseWireDecoder()
        let frame = try encoder.encodeRequest(
            DatabaseOperations.queryExecute,
            requestID: 42,
            target: .database,
            metadata: .init(
                traceID: "trace-42",
                idempotencyKey: "query-42"
            ),
            request: request
        )
        let decoded = try decoder.decodeRequest(
            DatabaseOperations.queryExecute,
            from: frame
        )

        #expect(decoded.requestID == 42)
        #expect(decoded.metadata.traceID == "trace-42")
        #expect(decoded.metadata.idempotencyKey == "query-42")
        #expect(decoded.request == request)
    }

    @Test("decoder accepts a borrowed frame view at an owner offset")
    func borrowedRequestFrameRoundTrip() throws {
        let encoded = try DatabaseWireEncoder().encodeRequest(
            DatabaseOperations.queryExecute,
            requestID: 43,
            target: .database,
            request: request
        )
        var storageBytes: [UInt8] = [0xA5]
        storageBytes.append(contentsOf: encoded)
        let storage = ByteString(storageBytes)
        let frame = storage[1..<storage.endIndex]

        let decoded = try DatabaseWireDecoder().decodeRequest(
            DatabaseOperations.queryExecute,
            from: frame
        )

        #expect(decoded.requestID == 43)
        #expect(decoded.request == request)
    }

    @Test("a request cannot be decoded through another operation")
    func operationMismatch() throws {
        let frame = try DatabaseWireEncoder().encodeRequest(
            DatabaseOperations.queryExecute,
            requestID: 7,
            target: .database,
            request: request
        )

        #expect(
            throws: DatabaseWireError.unexpectedOperationIdentifier(
                expected: .mutationExecute,
                actual: .queryExecute
            )
        ) {
            try DatabaseWireDecoder().decodeRequest(
                DatabaseOperations.mutationExecute,
                from: frame
            )
        }
    }

    @Test("request payload boundary preserves the selected operation")
    func requestPayloadRoundTrip() throws {
        let encoder = DatabaseWireEncoder()
        let decoder = DatabaseWireDecoder()
        let payload = try encoder.encodeRequestPayload(
            DatabaseOperations.queryExecute,
            request: request
        )

        let decoded = try decoder.decodeRequestPayload(
            DatabaseOperations.queryExecute,
            from: payload
        )

        #expect(decoded == request)
    }

    @Test("successful responses validate operation and request identity")
    func responseRoundTrip() throws {
        let encoder = DatabaseWireEncoder()
        let decoder = DatabaseWireDecoder()
        let response = QueryExecuteOperation.Response.boolean(
            try QueryBooleanResult(
                value: true,
                provenance: nil,
                consistency: try consistency()
            )
        )
        let frame = try encoder.encodeResponse(
            DatabaseOperations.queryExecute,
            requestID: 91,
            response: response
        )

        let decoded = try decoder.decodeResponse(
            DatabaseOperations.queryExecute,
            from: frame,
            matching: 91
        )
        guard case .success(.boolean(let value)) = decoded else {
            Issue.record("Expected a successful boolean response")
            return
        }
        #expect(value.value)
        #expect(
            throws: DatabaseWireError.unexpectedRequestIdentifier(
                expected: 92,
                actual: 91
            )
        ) {
            try decoder.decodeResponse(
                DatabaseOperations.queryExecute,
                from: frame,
                matching: 92
            )
        }
    }

    @Test("remote operation failures remain distinct from protocol failures")
    func remoteFailure() throws {
        let error = RemoteOperationError(
            category: .resourceLimit,
            code: "QUERY_BUDGET_EXCEEDED",
            message: "The query exceeded its work budget",
            retryability: .never
        )
        let frame = try DatabaseWireEncoder().encodeFailure(
            requestID: 33,
            operation: .queryExecute,
            error: error
        )

        let decoded = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperations.queryExecute,
            from: frame,
            matching: 33
        )
        guard case .failure(let decodedError) = decoded else {
            Issue.record("Expected a remote operation failure")
            return
        }
        #expect(decodedError == error)
    }

    @Test("encoded response payload borrows the final frame allocation")
    func responsePayloadOwnership() throws {
        let encoded = try DatabaseWireEncoder().encodeResponseAndPayload(
            DatabaseOperations.queryExecute,
            requestID: 12,
            response: QueryExecuteOperation.Response.boolean(
                try QueryBooleanResult(
                    value: true,
                    provenance: nil,
                    consistency: try consistency()
                )
            )
        )
        let frameAddress = try #require(
            encoded.frame.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        let payloadAddress = try #require(
            encoded.payload.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )

        #expect(payloadAddress == frameAddress + 22)
    }

    @Test("a persisted success payload can be decoded and replayed")
    func persistedResponsePayloadRoundTrip() throws {
        let encoder = DatabaseWireEncoder()
        let decoder = DatabaseWireDecoder()
        let response = QueryExecuteOperation.Response.boolean(
            try QueryBooleanResult(
                value: true,
                provenance: nil,
                consistency: try consistency()
            )
        )
        let encoded = try encoder.encodeResponseAndPayload(
            DatabaseOperations.queryExecute,
            requestID: 20,
            response: response
        )

        let decodedPayload = try decoder.decodeResponsePayload(
            DatabaseOperations.queryExecute,
            from: encoded.payload
        )
        guard case .boolean(let value) = decodedPayload else {
            Issue.record("Expected a boolean response payload")
            return
        }
        #expect(value.value)

        let replayedFrame = try encoder.encodeSuccessPayload(
            requestID: 21,
            operation: .queryExecute,
            payload: encoded.payload
        )
        let replayed = try decoder.decodeResponse(
            DatabaseOperations.queryExecute,
            from: replayedFrame,
            matching: 21
        )
        guard case .success(.boolean(let replayedValue)) = replayed else {
            Issue.record("Expected a replayed boolean response")
            return
        }
        #expect(replayedValue.value)
    }

    @Test("server payload SPI preserves opaque bounded state")
    func serverPayloadRoundTrip() throws {
        let value = ServerCursor(
            sequence: 7,
            continuation: ByteString([1, 2, 3]),
            details: try FieldObject([
                (key: "phase", value: .string("indexing")),
            ])
        )
        let payload = try DatabaseRuntimePayloadEncoder.encode(value)
        let decoded = try DatabaseRuntimePayloadDecoder.decode(
            ServerCursor.self,
            from: payload
        )

        #expect(decoded == value)
    }

    @Test("server semantic payloads use one canonical borrowed emission")
    func serverSemanticPayloadEmission() throws {
        let quad = RDFQuad(
            subject: .iri(try RDFIRI("urn:event:1")),
            predicate: RDFPredicateIRI(try RDFIRI("urn:event:startsAt")),
            object: .literal(
                RDFLiteral(
                    lexicalForm: "2026-07-26",
                    annotation: .typed(
                        XSDDatatype.date.typedLiteralDatatype
                    )
                )
            )
        )
        let encodedQuad = try DatabaseRuntimePayloadEncoder.encode(quad)
        #expect(
            try DatabaseRuntimePayloadDecoder.decode(
                RDFQuad.self,
                from: encodedQuad
            ) == quad
        )

        let term = GraphAlgorithmOperation.Term.rdf(
            .iri(try RDFIRI("urn:event:1"))
        )
        let encodedTerm = try DatabaseRuntimePayloadEncoder.encode(term)
        var measuredByteCount = 0
        var emittedBytes: [UInt8] = []
        try DatabaseRuntimePayloadEncoder.emit(
            term,
            prepare: { measuredByteCount = $0 },
            consume: { emittedBytes.append(contentsOf: $0) }
        )

        #expect(measuredByteCount == encodedTerm.count)
        #expect(ByteString(emittedBytes) == encodedTerm)
    }
}

private struct ServerCursor: DatabaseRuntimePayloadValue, Equatable {
    let sequence: UInt32
    let continuation: ByteString
    let details: FieldObject

    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        writer.writeUInt32(sequence)
        try writer.writeBytes(continuation)
        try details.encode(into: &writer)
    }

    init(
        sequence: UInt32,
        continuation: ByteString,
        details: FieldObject
    ) {
        self.sequence = sequence
        self.continuation = continuation
        self.details = details
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        self.init(
            sequence: try reader.readUInt32(),
            continuation: try reader.readBytes(),
            details: try FieldObject(from: &reader)
        )
    }
}
