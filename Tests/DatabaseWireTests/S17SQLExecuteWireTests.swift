import DatabaseKit
import DatabaseTypes
import Testing
@_spi(DatabaseExecution) @testable import DatabaseWire

@Suite("S17 closed complete SQL operation")
struct S17SQLExecuteWireTests {
    private var operation: DatabaseOperation<SQLExecuteOperation.Request, SQLExecuteOperation.Response> {
        DatabaseOperationCatalog.sqlExecute
    }

    @Test("Original text, statement and operational block share the canonical request envelope")
    func inputForms() throws {
        let statement = QueryStatement.select(SelectQuery(projection: [.expression(.parameter(position: 1), alias: "é")], source: .values([])))
        let block = try SQLBlock(steps: [.prepare(.init(name: "p", statement: statement)), .execute(.init(name: "p"))])
        let text = "-- é\r\nBEGIN; COPY t FROM STDIN;\nα\n\\.\nROLLBACK;"
        let parameters = [QueryParameter(position: 1, value: .primitive(.int64(7)))]
        let budget = ExecutionBudget(maximumRows: 0, maximumWorkUnits: 81,
            maximumIntermediateRows: 3, maximumIntermediateBytes: 99, timeoutMilliseconds: 5)
        for input: SQLExecuteOperation.Input in [.text(text), .statement(statement), .block(block)] {
            let request = SQLExecuteOperation.Request(input: input, parameters: parameters, budget: budget)
            let frame = try DatabaseWireEncoder().encodeTestDatabaseRequest(operation, requestID: 7, request: request)
            let decoded = try DatabaseWireDecoder().decodeRequest(operation, from: frame)
            #expect(decoded.requestID == 7)
            #expect(decoded.request == request)
            #expect(try DatabaseWireEncoder().encodeTestDatabaseRequest(operation, requestID: 7, request: request) == frame)
        }
    }

    @Test("SQL success has an independent fixed operation vector in each selected protocol")
    func successGolden() throws {
        let response = SQLExecuteOperation.Response(results: [.command(.commit, affectedRows: nil)])
        let frame = try DatabaseWireEncoder().encodeResponse(operation, requestID: 7, response: response)
        #if DATABASE_KIT_MULTI_BASE
        let version: UInt8 = 5
        #else
        let version: UInt8 = 3
        #endif
        let golden: [UInt8] = [0x44, 0x42, 0x57, 0x52, version, 0, 2,
            7, 0, 0, 0, 0, 0, 0, 0, 2, 2, 1, 7, 0, 0, 0, 1, 0, 0, 0, 2, 1, 0]
        #expect(frame == ByteString(golden))
        #expect(try DatabaseWireEncoder().measureSuccessResponse(operation, requestID: 7, response: response) == golden.count)
        guard case .success(let decoded) = try DatabaseWireDecoder().decodeResponse(operation, from: frame, matching: 7),
              case .command(.commit, nil) = decoded.results.first else {
            Issue.record("Expected the SQL command vector"); return
        }
        #expect(DatabaseOperationIdentifier.queryExecute.rawValue == 0x0201)
        #expect(DatabaseOperationIdentifier.sqlExecute.rawValue == 0x0202)
        #expect(throws: DatabaseWireError.invalidJobOperationFamily(0x0202)) {
            try JobOperationIdentifier(family: .sqlExecute, kind: "execute")
        }
        #expect(throws: DatabaseWireError.invalidJobOperationFamily(0x0202)) {
            try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
                try JobOperationIdentifier(validatedFamily: .sqlExecute, validatedKind: "execute").encode(into: &writer)
            }
        }
        let hostileJob = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            writer.writeUInt16(0x0202); try writer.writeString("execute")
        }
        var jobReader = DatabaseWireReader(hostileJob)
        #expect(throws: DatabaseWireError.invalidJobOperationFamily(0x0202)) {
            try JobOperationIdentifier(from: &jobReader)
        }
    }

    @Test("Ordered typed rows, COPY bytes, affected counts and duplicate labels survive frame release")
    func orderedResultsAndRetention() throws {
        let columns = [
            try QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: false),
            try QueryColumn(number: 2, name: "x", type: .sql(.json), isNullable: true),
        ]
        let json = try QueryJSONValue(bytes: ByteString(utf8: "{\"é\":null}"), limits: DatabaseWireLimits.default.queryValueLimits)
        let row = QueryRow(values: [.primitive(.int32(8)), .json(json)],
            annotations: try FieldObject([("source", .string("t"))]), version: ByteString([1, 2]))
        let retained: SQLExecuteOperation.Rows
        do {
            let response = SQLExecuteOperation.Response(results: [
                .command(.savepoint, affectedRows: nil),
                .rows(try .init(columns: columns, rows: [row], affectedRows: 42)),
                .copy(bytes: ByteString([0, 10, 255]), affectedRows: 6),
                .command(.rollback, affectedRows: nil),
            ])
            let frame = try DatabaseWireEncoder().encodeResponse(operation, requestID: 9, response: response)
            guard case .success(let decoded) = try DatabaseWireDecoder().decodeResponse(operation, from: frame, matching: 9),
                  decoded.results.count == 4,
                  case .command(.savepoint, nil) = decoded.results[0],
                  case .rows(let rows) = decoded.results[1],
                  case .copy(let bytes, 6) = decoded.results[2],
                  case .command(.rollback, nil) = decoded.results[3] else {
                Issue.record("Expected all ordered outcomes"); return
            }
            #expect(bytes == ByteString([0, 10, 255]))
            var iterator = rows.makeRowIterator()
            let decodedRow = try #require(try iterator.next())
            guard case .json(let lexical) = decodedRow.values[1] else {
                Issue.record("Expected retained lexical JSON"); return
            }
            let frameAddress = try #require(frame.withUnsafeBytes { $0.baseAddress.map { UInt(bitPattern: $0) } })
            let jsonAddress = try #require(lexical.bytes.withUnsafeBytes { $0.baseAddress.map { UInt(bitPattern: $0) } })
            #expect(jsonAddress >= frameAddress)
            #expect(jsonAddress + UInt(lexical.bytes.count) <= frameAddress + UInt(frame.count))
            retained = rows
        }
        #expect(retained.columns == columns)
        #expect(retained.rowCount == 1)
        #expect(retained.affectedRows == 42)
        var iterator = retained.makeRowIterator()
        #expect(try iterator.next() == row)
        #expect(try iterator.next() == nil)
        // Re-encoding the lazy retained rows must validate the same bounded cells.
        let response = SQLExecuteOperation.Response(results: [.rows(retained)])
        let frame = try DatabaseWireEncoder().encodeResponse(operation, requestID: 9, response: response)
        #expect(try DatabaseWireEncoder().measureSuccessResponse(operation, requestID: 9, response: response) == frame.count)
    }

    @Test("Zero rows retain duplicate declarations and invalid materialized cells fail")
    func emptyRowsAndInvalidCells() throws {
        let columns = [try QueryColumn(number: 1, name: "", type: .sql(.integer), isNullable: false),
                       try QueryColumn(number: 2, name: "", type: .sql(.text), isNullable: true)]
        let response = SQLExecuteOperation.Response(results: [.rows(try .init(columns: columns, rows: []))])
        let frame = try DatabaseWireEncoder().encodeResponse(operation, requestID: 1, response: response)
        guard case .success(let decoded) = try DatabaseWireDecoder().decodeResponse(operation, from: frame, matching: 1),
              case .rows(let rows) = decoded.results[0] else { Issue.record("Expected empty typed rows"); return }
        #expect(rows.columns == columns)
        #expect(rows.rowCount == 0)
        var iterator = rows.makeRowIterator()
        #expect(try iterator.next() == nil)
        #expect(throws: DatabaseWireError.invalidRowValueCount(expected: 2, actual: 0)) {
            try SQLExecuteOperation.Rows(columns: columns, rows: [QueryRow(values: [])])
        }
        #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) {
            try SQLExecuteOperation.Rows(columns: columns, rows: [QueryRow(values: [.primitive(.null), .primitive(.null)])])
        }
    }

    @Test("All command identities have fixed closed tags, including DDL and checkpoints")
    func commandTags() throws {
        let kinds: [SQLCommandKind] = [.begin, .commit, .rollback, .set, .show, .reset,
            .prepare, .execute, .deallocate, .explain, .copy, .createSchema, .alterSchema, .dropSchema,
            .createTable, .alterTable, .dropTable, .createIndex, .dropIndex, .createView, .dropView,
            .createMaterializedView, .refreshMaterializedView, .dropMaterializedView, .setConstraints,
            .createSequence, .alterSequence, .dropSequence, .insert, .update, .delete, .merge, .truncate,
            .savepoint, .rollbackTo, .release]
        for (tag, kind) in kinds.enumerated() {
            #expect(SQLCommandWireCodec.tag(kind) == UInt8(tag))
            #expect(try SQLCommandWireCodec.kind(UInt8(tag)) == kind)
        }
        for tag: UInt8 in [36, 255] {
            #expect(throws: DatabaseWireError.invalidSQLResponse) { try SQLCommandWireCodec.kind(tag) }
        }
    }

    @Test("Truncation, trailing bytes, unknown tags and empty results never decode successfully")
    func malformedPayloads() throws {
        let response = SQLExecuteOperation.Response(results: [.copy(bytes: ByteString([1, 2]), affectedRows: UInt64.max)])
        let payload = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try response.encode(into: &writer) }
        let bytes = Array(payload)
        for count in 0..<bytes.count {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder().decodeResponsePayload(operation, from: ByteString(Array(bytes.prefix(count))))
            }
        }
        #expect(throws: DatabaseWireError.trailingBytes) {
            try DatabaseWireDecoder().decodeResponsePayload(operation, from: ByteString(bytes + [0]))
        }
        for invalid in [[UInt8](repeating: 0, count: 4), [1, 0, 0, 0, 3], [1, 0, 0, 0, 2, 255]] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder().decodeResponsePayload(operation, from: ByteString(invalid))
            }
        }
        let request = try DatabaseWireEncoder().encodeRequestPayload(operation, request: .init(input: .text("é")))
        let requestBytes = Array(request)
        for count in 0..<requestBytes.count {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder().decodeRequestPayload(operation, from: ByteString(Array(requestBytes.prefix(count))))
            }
        }
        #expect(throws: DatabaseWireError.trailingBytes) {
            try DatabaseWireDecoder().decodeRequestPayload(operation, from: ByteString(requestBytes + [0]))
        }
        var invalidRequest = Array(request); invalidRequest[0] = 255
        #expect(throws: DatabaseWireError.invalidQueryInput(255)) {
            try DatabaseWireDecoder().decodeRequestPayload(operation, from: ByteString(invalidRequest))
        }
    }

    @Test("Full-frame, COPY, collection and shared outcome object ledgers enforce exact boundaries")
    func resourceBoundaries() throws {
        let copy = SQLExecuteOperation.Outcome.copy(bytes: ByteString([1, 2, 3]), affectedRows: 1)
        let exactCopy = try sqlLimits(bytes: 3)
        let copyBytes = try DatabaseWireWriter.encode(limits: exactCopy) { writer throws(DatabaseWireError) in
            try copy.encode(into: &writer)
        }
        var copyReader = DatabaseWireReader(copyBytes, limits: exactCopy)
        guard case .copy(let retained, 1) = try SQLExecuteOperation.Outcome(from: &copyReader) else {
            Issue.record("Expected exact COPY byte boundary"); return
        }
        #expect(retained == ByteString([1, 2, 3]))
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireWriter.encode(limits: sqlLimits(bytes: 2)) { writer throws(DatabaseWireError) in try copy.encode(into: &writer) }
        }
        let request = SQLExecuteOperation.Request(input: .text("é"))
        let exactString = try sqlLimits(string: 2)
        let requestBytes = try DatabaseWireEncoder(limits: exactString).encodeRequestPayload(operation, request: request)
        #expect(try DatabaseWireDecoder(limits: exactString).decodeRequestPayload(operation, from: requestBytes) == request)
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireDecoder(limits: sqlLimits(string: 1)).decodeRequestPayload(operation, from: requestBytes)
        }
        let response = SQLExecuteOperation.Response(results: [.copy(bytes: ByteString([1, 2, 3]), affectedRows: 1)])
        let frame = try DatabaseWireEncoder().encodeResponse(operation, requestID: 1, response: response)
        let exact = try sqlLimits(frame: frame.count)
        #expect(try DatabaseWireEncoder(limits: exact).measureSuccessResponse(operation, requestID: 1, response: response) == frame.count)
        for restrictive in [try sqlLimits(frame: frame.count - 1), try sqlLimits(bytes: 2), try sqlLimits(collection: 0), try sqlLimits(depth: 1)] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireEncoder(limits: restrictive).encodeResponse(operation, requestID: 1, response: response)
            }
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder(limits: restrictive).decodeResponse(operation, from: frame, matching: 1)
            }
        }
        let fullExact = try sqlLimits(depth: 2, objects: 3)
        #expect(try DatabaseWireEncoder(limits: fullExact).encodeResponse(operation, requestID: 1, response: response) == frame)
        guard case .success = try DatabaseWireDecoder(limits: fullExact).decodeResponse(operation, from: frame, matching: 1)
        else { Issue.record("Expected exact enclosing response admission"); return }
        #expect(throws: DatabaseWireError.objectBudgetExceeded(actual: 3, maximum: 2)) {
            try DatabaseWireDecoder(limits: sqlLimits(depth: 2, objects: 2)).decodeResponse(operation, from: frame, matching: 1)
        }
        let body = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try response.encode(into: &writer) }
        #expect(try DatabaseWireDecoder(limits: sqlLimits(depth: 1, objects: 2)).decodeResponsePayload(operation, from: body).results.count == 1)
        try requestEnvelopeAdmission()
        try rootRetentionAdmission(responseFrame: frame)
        let rows = try SQLExecuteOperation.Rows(columns: [QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: false)],
            rows: [QueryRow(values: [.primitive(.int32(1))])])
        let one = SQLExecuteOperation.Response(results: [.rows(rows)])
        let two = SQLExecuteOperation.Response(results: [.rows(rows), .rows(rows)])
        let oneBytes = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try one.encode(into: &writer) }
        var calibration = DatabaseWireReader(oneBytes)
        _ = try SQLExecuteOperation.Response(from: &calibration)
        let limit = try sqlLimits(objects: calibration.registeredObjectCount)
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireWriter.encode(limits: limit) { writer throws(DatabaseWireError) in try two.encode(into: &writer) }
        }
        let twoBytes = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try two.encode(into: &writer) }
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireDecoder(limits: limit).decodeResponsePayload(operation, from: twoBytes)
        }
    }

    private func requestEnvelopeAdmission() throws {
        let request = SQLExecuteOperation.Request(input: .text(""))
        let metadata = OperationRequestMetadata(traceID: "é", idempotencyKey: "k")
        #if DATABASE_KIT_MULTI_BASE
        let target = DatabaseOperationTarget.composition(try .derived([Base.ID("a"), Base.ID("b")]))
        let frame = try DatabaseWireEncoder().encodeRequest(operation, requestID: 4,
            target: target, metadata: metadata, request: request)
        let exactObjects = 3 // Two target members and the enclosing payload.
        #else
        let frame = try DatabaseWireEncoder().encodeRequest(operation, requestID: 4,
            metadata: metadata, request: request)
        let exactObjects = 1 // The enclosing payload.
        #endif
        let exact = try sqlLimits(string: 2, depth: 1, objects: exactObjects)
        let decoded = try DatabaseWireDecoder(limits: exact).decodeRequest(operation, from: frame)
        #expect(decoded.request == request)
        #expect(decoded.metadata == metadata)
        #if DATABASE_KIT_MULTI_BASE
        #expect(decoded.target == target)
        #expect(try DatabaseWireEncoder(limits: exact).encodeRequest(operation, requestID: 4,
            target: target, metadata: metadata, request: request) == frame)
        #else
        #expect(try DatabaseWireEncoder(limits: exact).encodeRequest(operation, requestID: 4,
            metadata: metadata, request: request) == frame)
        #endif
        let raw = try DatabaseWireDecoder().decodeRequestEnvelope(frame)
        #if DATABASE_KIT_MULTI_BASE
        let sameValue = DatabaseWireRequestEnvelope(requestID: raw.requestID, operation: raw.operation,
            target: raw.target, metadata: raw.metadata, payload: raw.payload)
        #else
        let sameValue = DatabaseWireRequestEnvelope(requestID: raw.requestID, operation: raw.operation,
            metadata: raw.metadata, payload: raw.payload)
        #endif
        #expect(raw.payloadAdmission != nil)
        #expect(sameValue.payloadAdmission == nil)
        #expect(raw == sameValue)
        #expect(Set([raw, sameValue]).count == 1)
        #expect(try DatabaseWireDecoder(limits: exact).decodeRequest(operation, from: raw) == request)
        for limit in [try sqlLimits(depth: 0), try sqlLimits(objects: exactObjects - 1)] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder(limits: limit).decodeRequest(operation, from: frame)
            }
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder(limits: limit).decodeRequest(operation, from: raw)
            }
        }
        #expect(throws: DatabaseWireError.stringTooLarge(actual: 2, maximum: 1)) {
            try DatabaseWireDecoder(limits: sqlLimits(string: 1)).decodeRequest(operation, from: frame)
        }
        let body = try DatabaseWireEncoder().encodeRequestPayload(operation, request: request)
        #expect(try DatabaseWireDecoder(limits: sqlLimits(depth: 0, objects: 0)).decodeRequestPayload(operation, from: body) == request)
        // The decoded payload still owns the full frame, including its header.
        let bodySized = try sqlLimits(frame: raw.payload.count)
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireDecoder(limits: bodySized).decodeRequest(operation, from: raw)
        }
    }

    private func rootRetentionAdmission(responseFrame: ByteString) throws {
        let request = SQLExecuteOperation.Request(input: .text(""))
        let requestFrame = try DatabaseWireEncoder().encodeTestDatabaseRequest(operation, requestID: 5, request: request)
        for frame in [requestFrame, responseFrame] {
            let backing = ByteString.copying(count: frame.count + 128) { destination in
                destination.initializeMemory(as: UInt8.self, repeating: 0)
                frame.withUnsafeBytes { destination.copyMemory(from: $0) }
            }
            let known = backing[0..<frame.count]
            let unknown = ByteString(retaining: UnmeasuredSQLFrameOwner(bytes: Array(frame)))
            for rejected in [known, unknown] {
                let limits = try sqlLimits(frame: frame.count)
                #expect(throws: DatabaseWireError.self) {
                    if frame == requestFrame {
                        _ = try DatabaseWireDecoder(limits: limits).decodeRequest(operation, from: rejected)
                    } else {
                        _ = try DatabaseWireDecoder(limits: limits).decodeResponse(operation, from: rejected, matching: 1)
                    }
                }
            }
        }
        let requestBody = try DatabaseWireEncoder().encodeRequestPayload(operation, request: request)
        let unknownBody = ByteString(retaining: UnmeasuredSQLFrameOwner(bytes: Array(requestBody)))
        #expect(throws: DatabaseWireError.invalidQueryValue(.unknownRetainedByteCount)) {
            try DatabaseWireDecoder().decodeRequestPayload(operation, from: unknownBody)
        }
    }
}

private struct UnmeasuredSQLFrameOwner: ByteStringOwner {
    let bytes: [UInt8]
    var count: Int { bytes.count }
    func borrowBytes(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
        try bytes.withUnsafeBytes(body)
    }
}

func sqlLimits(frame: Int = 100_000, string: Int = 10_000, bytes: Int = 100_000,
               collection: Int = 1000, depth: Int = 64, objects: Int = 100_000) throws -> DatabaseWireLimits {
    try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string,
        maximumByteStringBytes: bytes, maximumCollectionCount: collection,
        maximumNestingDepth: depth, maximumObjectCount: objects)
}
