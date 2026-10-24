import DatabaseKit
import DatabaseTypes
import Testing
@_spi(DatabaseExecution) @testable import DatabaseWire

@Suite("S17 typed SQL remote diagnostics")
struct S17SQLDiagnosticWireTests {
    @Test("Every diagnostic category preserves exact SQLSTATE, source position and identifiers")
    func categoryAndMetadataRoundTrip() throws {
        let categories: [SQLDiagnosticCategory] = [.syntax, .name, .type, .cardinality,
            .constraint, .numeric, .data, .serialization, .transaction, .cancellation,
            .unsupported, .resource, .authorization, .internalError]
        for (tag, category) in categories.enumerated() {
            let diagnostic = try SQLDiagnostic(sqlState: "23505", category: category,
                message: "é failure", position: UInt64.max, schema: "Σ", table: "t", column: "c", constraint: "unique")
            let error = try RemoteOperationError(category: .constraint, code: "sql_failed", message: "request failed",
                retryability: .never, details: FieldObject([("cleanup", .bool(true))]), sqlDiagnostic: diagnostic)
            #expect(try error.sqlDiagnostic() == diagnostic)
            #expect(error.details["cleanup"] == .bool(true))
            guard case .object(let object) = error.details["sqlDiagnostic"] else { Issue.record("Missing reserved object"); return }
            #expect(object["category"] == .uint8(UInt8(tag)))
            let frame = try DatabaseWireEncoder().encodeFailure(requestID: 2, operation: .queryExecute, error: error)
            guard case .failure(let decoded) = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.queryExecute, from: frame, matching: 2) else {
                Issue.record("Expected typed remote failure"); return
            }
            #expect(decoded == error)
            #expect(try decoded.sqlDiagnostic() == diagnostic)
        }
    }

    @Test("Absent diagnostic metadata leaves existing generic failure bytes unchanged")
    func genericFailureGoldenUnchanged() throws {
        let error = RemoteOperationError(category: .invalidRequest, code: "e", message: "m", retryability: .never)
        #expect(try error.sqlDiagnostic() == nil)
        let frame = try DatabaseWireEncoder().encodeFailure(requestID: 1, operation: .queryExecute, error: error)
        let version: UInt8 = UInt8(DatabaseWireEncoder.protocolVersion)
        let golden: [UInt8] = [0x44, 0x42, 0x57, 0x52, version, 0, 2,
            1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 1,
            1, 0, 0, 0, 101, 1, 0, 0, 0, 109, 1, 0, 0, 0, 0]
        #expect(frame == ByteString(golden))
    }

    @Test("Malformed reserved metadata fails at typed access, generic encoding and generic decoding")
    func malformedReservedMetadata() throws {
        let valid: [(key: String, value: FieldValue)] = [
            ("sqlState", .string("42601")), ("category", .uint8(0)), ("message", .string("syntax"))]
        let malformed: [FieldValue] = [
            .null, .string("42601"), .object(FieldObject()),
            .object(try FieldObject(Array(valid.dropLast()))),
            .object(try FieldObject(valid + [("unexpected", .string("x"))])),
            .object(try FieldObject(valid.filter { $0.key != "category" } + [("category", .uint8(255))])),
            .object(try FieldObject(valid.filter { $0.key != "sqlState" } + [("sqlState", .string("bad"))])),
            .object(try FieldObject(valid + [("position", .uint64(0))])),
            .object(try FieldObject(valid + [("position", .int64(1))])),
            .object(try FieldObject(valid + [("schema", .null)])),
        ]
        for value in malformed {
            let details = try FieldObject([("sqlDiagnostic", value)])
            let error = RemoteOperationError(category: .invalidRequest, code: "sql", message: "invalid",
                retryability: .never, details: details)
            #expect(throws: DatabaseWireError.invalidSQLDiagnostic) { try error.sqlDiagnostic() }
            #expect(throws: DatabaseWireError.invalidSQLDiagnostic) {
                try DatabaseWireEncoder().encodeFailure(requestID: 1, operation: .queryExecute, error: error)
            }
            // Bypass the validating failure encoder to represent hostile peer bytes.
            let hostile = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
                for byte: UInt8 in [0x44, 0x42, 0x57, 0x52] { writer.writeUInt8(byte) }
                writer.writeUInt16(DatabaseWireEncoder.protocolVersion); writer.writeUInt8(2)
                writer.writeUInt64(1); writer.writeUInt16(0x0201); writer.writeUInt8(2)
                OperationErrorCategory.invalidRequest.encode(into: &writer)
                try writer.writeString("sql"); try writer.writeString("invalid")
                OperationRetryability.never.encode(into: &writer)
                try details.encode(into: &writer)
            }
            #expect(throws: DatabaseWireError.invalidSQLDiagnostic) {
                try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: hostile, matching: 1)
            }
        }
    }

    @Test("Reserved-key collisions reject instead of overwriting mapper details and diagnostic limits stay bounded")
    func collisionAndLimits() throws {
        let diagnostic = try SQLDiagnostic(sqlState: "42601", category: .syntax, message: "é", position: 1)
        let details = try FieldObject([("sqlDiagnostic", .null)])
        #expect(throws: DatabaseWireError.invalidSQLDiagnostic) {
            try RemoteOperationError(category: .invalidRequest, code: "x", message: "x",
                retryability: .never, details: details, sqlDiagnostic: diagnostic)
        }
        let error = try RemoteOperationError(category: .invalidRequest, code: "x", message: "x",
            retryability: .never, sqlDiagnostic: diagnostic)
        let frame = try DatabaseWireEncoder().encodeFailure(requestID: 1, operation: .queryExecute, error: error)
        for limits in [try sqlLimits(string: 4), try sqlLimits(objects: 2), try sqlLimits(depth: 1)] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireEncoder(limits: limits).encodeFailure(requestID: 1, operation: .queryExecute, error: error)
            }
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireDecoder(limits: limits).decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 1)
            }
        }
    }
}
