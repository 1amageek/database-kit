import DatabaseKit
import DatabaseTypes
import DatabaseWire
import Testing

@Suite("Public DatabaseWire boundary")
struct DatabaseWireBoundaryTests {
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

    @Test("decoder accepts a borrowed frame whose index does not start at zero")
    func slicedRequestRoundTrip() throws {
        let encoded = try DatabaseWireEncoder().encodeRequest(
            DatabaseOperations.queryExecute,
            requestID: 43,
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

    @Test("successful responses validate operation and request identity")
    func responseRoundTrip() throws {
        let encoder = DatabaseWireEncoder()
        let decoder = DatabaseWireDecoder()
        let response = QueryExecuteOperation.Response.boolean(true)
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
        #expect(value)
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
            response: QueryExecuteOperation.Response.boolean(true)
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
}
