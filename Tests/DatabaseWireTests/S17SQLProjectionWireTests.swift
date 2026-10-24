import DatabaseKit
import DatabaseTypes
import Testing
@_spi(DatabaseExecution) @testable import DatabaseWire

@Suite("S17 scoped SQL response projection")
struct S17SQLProjectionWireTests {
    private var column: QueryColumn {
        get throws {
            try QueryColumn(number: 1, name: "é", type: .sql(.text), isNullable: false)
        }
    }

    @Test("Scoped projection and materialized operation encode identical complete frames")
    func canonicalProjection() throws {
        let column = try column
        let annotations = try FieldObject([("a", .string("metadata"))])
        let version = ByteString([1, 2, 3])
        let row = QueryRow(values: [.primitive(.string("value"))], annotations: annotations, version: version)
        let quad = RDFQuad(subject: .iri(try RDFIRI("urn:s")),
            predicate: RDFPredicateIRI(try RDFIRI("urn:p")), object: .iri(try RDFIRI("urn:o")))
        let response = try SQLExecuteOperation.Response(results: [
            .rows(try .init(columns: [column], rows: [row], affectedRows: 7)),
            .rows(try .init(columns: [column], rows: [])),
            .copy(bytes: ByteString([0, 255]), affectedRows: 8),
            .command(.createTable, affectedRows: nil),
            makeTestBooleanResponse(true, snapshotVersion: 19),
            .rdfGraph(makeTestRDFGraphPage(quads: [quad], snapshotVersion: 19)),
        ])
        func project(_ response: inout QueryResponseWriter) throws {
            try response.writeRows(columnCount: 1, rowCount: 1, affectedRows: 7) { rows in
                try rows.writeColumn(column)
                try rows.beginRow()
                try rows.writeValue(.primitive(.string("value")))
                try rows.endRow(annotations: annotations, version: version)
            }
            try response.writeRows(columnCount: 1, rowCount: 0, affectedRows: nil) { rows in try rows.writeColumn(column) }
            try response.writeCopy(bytes: ByteString([0, 255]), affectedRows: 8)
            try response.writeCommand(.createTable, affectedRows: nil)
            #if DATABASE_KIT_MULTI_BASE
            let consistency = try makeTestReadConsistency(version: 19)
            try response.writeBoolean(QueryBooleanResult(value: true, provenance: nil, consistency: consistency))
            try response.writeRDFGraph(quadCount: 1, consistency: consistency) { quads in try quads.write(quad) }
            #else
            try response.writeBoolean(true)
            try response.writeRDFGraph(quadCount: 1, snapshotVersion: 19) { quads in try quads.write(quad) }
            #endif
        }
        let encoder = DatabaseWireEncoder()
        let size = try encoder.measureQueryResponse(requestID: 31, resultCount: 6, body: project)
        let frame = try ByteString.copying(count: size) { destination in
            try encoder.encodeQueryResponse(requestID: 31, resultCount: 6, into: destination, body: project)
        }
        #expect(frame == (try encoder.encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 31, response: response)))
        #expect(size == (try encoder.measureSuccessResponse(DatabaseOperationCatalog.queryExecute, requestID: 31, response: response)))
        guard case .success(let decoded) = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.queryExecute, from: frame, matching: 31),
              case .rows(let rows) = decoded.results[0] else { Issue.record("Expected projected rows"); return }
        var iterator = rows.makeRowIterator()
        #expect(try iterator.next() == row)
        #expect(try iterator.next() == nil)
    }

    @Test("Declared result, column, row and cell counts must all be completed exactly")
    func declaredCounts() throws {
        let encoder = DatabaseWireEncoder()
        let column = try column
        #expect(throws: DatabaseWireError.invalidSQLResponse) {
            try encoder.measureQueryResponse(requestID: 1, resultCount: 0) { _ in }
        }
        let bad: [(inout QueryResponseWriter) throws -> Void] = [
            { _ in },
            { writer in
                try writer.writeCommand(.begin, affectedRows: nil)
                try writer.writeCommand(.commit, affectedRows: nil)
            },
            { writer in try writer.writeRows(columnCount: 1, rowCount: 0, affectedRows: nil) { _ in } },
            { writer in try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: nil) { rows in try rows.writeColumn(column) } },
            { writer in try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: nil) { rows in
                try rows.writeColumn(column); try rows.beginRow(); try rows.endRow()
            } },
            { writer in try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: nil) { rows in
                try rows.writeColumn(column); try rows.beginRow(); try rows.writeValue(.primitive(.string("x")))
            } },
        ]
        for body in bad {
            #expect(throws: DatabaseWireError.invalidSQLResponse) {
                try encoder.measureQueryResponse(requestID: 1, resultCount: 1, body: body)
            }
        }
    }

    @Test("Schema order, row phase, type and nullability violations fail before a frame is accepted")
    func schemaAndPhase() throws {
        let column = try column
        let encoder = DatabaseWireEncoder()
        #expect(throws: DatabaseWireError.invalidSQLResponse) {
            try encoder.measureQueryResponse(requestID: 1, resultCount: 1) { writer in
                try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: nil) { rows in try rows.beginRow() }
            }
        }
        #expect(throws: DatabaseWireError.invalidSQLResponse) {
            try encoder.measureQueryResponse(requestID: 1, resultCount: 1) { writer in
                try writer.writeRows(columnCount: 1, rowCount: 0, affectedRows: nil) { rows in
                    try rows.writeColumn(column); try rows.writeColumn(column)
                }
            }
        }
        for value: QueryValue in [.primitive(.null), .primitive(.int64(1))] {
            #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) {
                try encoder.measureQueryResponse(requestID: 1, resultCount: 1) { writer in
                    try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: nil) { rows in
                        try rows.writeColumn(column); try rows.beginRow(); try rows.writeValue(value)
                    }
                }
            }
        }
    }

    @Test("Native admission errors survive measurement and partial encoding without conversion")
    func nativeProjectionFailure() throws {
        let encoder = DatabaseWireEncoder()
        #expect(throws: ProjectionFailure.reservation) {
            try encoder.measureQueryResponse(requestID: 1, resultCount: 1) { writer in
                try writer.writeRows(columnCount: 0, rowCount: 0, affectedRows: nil) { _ in
                    throw ProjectionFailure.reservation
                }
            }
        }
        #expect(throws: ProjectionFailure.reservation) {
            try ByteString.copying(count: 100) { destination in
                try encoder.encodeQueryResponse(requestID: 1, resultCount: 1, into: destination) { writer in
                    try writer.writeRows(columnCount: 0, rowCount: 0, affectedRows: nil) { _ in
                        throw ProjectionFailure.reservation
                    }
                }
            }
        }
    }

    @Test("The exact borrowed output range is initialized and short or long destinations fail")
    func destinationBounds() throws {
        let encoder = DatabaseWireEncoder()
        func project(_ response: inout QueryResponseWriter) throws { try response.writeCommand(.commit, affectedRows: nil) }
        let count = try encoder.measureQueryResponse(requestID: 1, resultCount: 1, body: project)
        for size in [count - 1, count + 1] {
            #expect(throws: DatabaseWireError.self) {
                try ByteString.copying(count: size) { destination in
                    try encoder.encodeQueryResponse(requestID: 1, resultCount: 1, into: destination, body: project)
                }
            }
        }
        var bytes = [UInt8](repeating: 0xa5, count: count + 2)
        try bytes.withUnsafeMutableBytes { destination in
            let bounded = UnsafeMutableRawBufferPointer(rebasing: destination[1..<(count + 1)])
            try encoder.encodeQueryResponse(requestID: 1, resultCount: 1, into: bounded, body: project)
        }
        #expect(bytes.first == 0xa5)
        #expect(bytes.last == 0xa5)
        let frame = ByteString(Array(bytes[1..<(count + 1)]))
        guard case .success(let decoded) = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.queryExecute, from: frame, matching: 1),
              case .command(.commit, nil) = decoded.results[0] else { Issue.record("Expected exact range encoding"); return }
    }

    @Test("Projection applies full frame, collection and nesting budgets before acceptance")
    func projectionLimits() throws {
        func project(_ writer: inout QueryResponseWriter) throws { try writer.writeCopy(bytes: ByteString([1, 2, 3]), affectedRows: 1) }
        let count = try DatabaseWireEncoder().measureQueryResponse(requestID: 1, resultCount: 1, body: project)
        #expect(try DatabaseWireEncoder(limits: sqlLimits(frame: count)).measureQueryResponse(requestID: 1, resultCount: 1, body: project) == count)
        for limits in [try sqlLimits(frame: count - 1), try sqlLimits(bytes: 2)] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireEncoder(limits: limits).measureQueryResponse(requestID: 1, resultCount: 1, body: project)
            }
        }
        for limits in [try sqlLimits(collection: 1), try sqlLimits(depth: 1)] {
            #expect(throws: DatabaseWireError.self) {
                try DatabaseWireEncoder(limits: limits).measureQueryResponse(requestID: 1, resultCount: 2) { writer in
                    try project(&writer)
                    try project(&writer)
                }
            }
        }
        #expect(throws: DatabaseWireError.self) {
            try DatabaseWireEncoder().measureQueryResponse(requestID: 1, resultCount: 1) { writer in
                try writer.writeRows(columnCount: -1, rowCount: 0, affectedRows: nil) { _ in }
            }
        }
    }
}

private enum ProjectionFailure: Error, Equatable { case reservation }
