import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Typed positional query pages")
struct QueryTypedPageTests {
    @Test("lazy pages admit encoded ownership before reconciling actual JSONB row storage")
    func jsonbMaterializationRetentionBoundary() throws {
        let root = try QueryJSONBNode.array(Array(repeating: .null, count: 64),
                                            limits: DatabaseWireLimits.default.queryValueLimits)
        let value = try QueryJSONBValue(root: root, limits: DatabaseWireLimits.default.queryValueLimits)
        let columns = [try QueryColumn(number: 1, name: "json", type: .sql(.jsonb), isNullable: false)]
        let page = try makeTestQueryRowPage(columns: columns, rows: [QueryRow(values: [.jsonb(value)])],
                                          continuation: nil, snapshotVersion: 9)
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.queryExecute, requestID: 19, response: .rows(page)
        )
        let retained = try #require(frame.retainedByteCount)
        #expect(root.storageFootprint.retainedStorageByteCount > UInt64(retained))
        let limits = try DatabaseWireLimits(maximumFrameBytes: retained, maximumStringBytes: retained,
            maximumByteStringBytes: retained, maximumCollectionCount: 1024,
            maximumNestingDepth: 32, maximumObjectCount: 4096)
        let response = try DatabaseWireDecoder(limits: limits).decodeResponse(
            DatabaseOperationCatalog.queryExecute, from: frame, matching: 19
        )
        guard case .success(.rows(let decoded)) = response else {
            Issue.record("Expected a lazy JSONB page"); return
        }
        #expect(decoded.retainedEncodedRows != nil)
        #expect(decoded.rowCount == 1)
        var iterator = decoded.makeRowIterator()
        var publishedRow: QueryRow?
        do {
            publishedRow = try iterator.next()
            Issue.record("Expected actual JSONB storage to exceed the row retention limit")
        } catch .invalidQueryValue(.resourceLimit(let resource, let actual, let maximum)) {
            #expect(resource == "retainedBytes")
            #expect(actual > maximum)
            #expect(maximum == UInt64(retained))
        }
        #expect(publishedRow == nil)
    }

    @Test("primitive array NULL elements preserve lazy round trips without admitting outer NULL or wrong element types")
    func primitiveArrayNullableElements() throws {
        let columns = [try QueryColumn(number: 1, name: "values",
                                       type: .primitive(.int64, isArray: true), isNullable: false)]
        let row = QueryRow(values: [.primitive(.array([.int64(1), .null]))])
        let page = try makeTestQueryRowPage(columns: columns, rows: [row],
                                          continuation: nil, snapshotVersion: 9)
        let frame = try DatabaseWireEncoder().encodeResponse(
            DatabaseOperationCatalog.queryExecute, requestID: 18, response: .rows(page)
        )
        let response = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.queryExecute, from: frame, matching: 18
        )
        guard case .success(.rows(let decoded)) = response else {
            Issue.record("Expected a primitive array page")
            return
        }
        #expect(decoded.retainedEncodedRows != nil)
        var iterator = decoded.makeRowIterator()
        #expect(try iterator.next() == row)
        #expect(try iterator.next() == nil)

        for invalid in [QueryRow(values: [.primitive(.array([.int64(1), .string("wrong")]))]),
                        QueryRow(values: [.primitive(.null)])] {
            let payload = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
                try invalid.encode(into: &writer)
            }
            var reader = DatabaseWireReader(payload)
            #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) {
                try QueryRow.validate(from: &reader, columns: columns)
            }
        }
    }

    @Test("duplicate labels and zero-row declarations survive the response path")
    func duplicateAndEmptyColumns() throws {
        let columns = [
            try QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: true),
            try QueryColumn(number: 2, name: "x", type: .sql(.bigint), isNullable: false),
        ]
        for rows in [[], [QueryRow(values: [.primitive(.null), .primitive(.int64(2))])]] {
            let page = try makeTestQueryRowPage(columns: columns, rows: rows,
                                              continuation: nil, snapshotVersion: 9)
            let frame = try DatabaseWireEncoder().encodeResponse(
                DatabaseOperationCatalog.queryExecute, requestID: 8, response: .rows(page)
            )
            let response = try DatabaseWireDecoder().decodeResponse(
                DatabaseOperationCatalog.queryExecute, from: frame, matching: 8
            )
            guard case .success(.rows(let decoded)) = response else {
                Issue.record("Expected typed positional rows")
                return
            }
            #expect(decoded.columns == columns)
            #expect(try decoded.materializedRows(maximumCount: 1) == rows)
        }
    }

    @Test("materialized page rejects arity, type and nonnullable NULL before publication")
    func invalidPageCells() throws {
        let columns = [try QueryColumn(number: 1, name: "value", type: .sql(.integer), isNullable: false)]
        for row in [QueryRow(values: []), QueryRow(values: [.primitive(.string("wrong"))]),
                    QueryRow(values: [.primitive(.null)])] {
            #expect(throws: DatabaseWireError.self) {
                _ = try makeTestQueryRowPage(columns: columns, rows: [row],
                                            continuation: nil, snapshotVersion: nil)
            }
        }
    }

    @Test("rich parameter and literal 18 preserve explicit type and numeric display scale")
    func richParameterAndLiteral() throws {
        let numeric = try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 2)
        let type = QueryColumnType.sql(.decimal(precision: 4, scale: 2))
        let parameter = QueryParameter(position: 1, name: "amount", value: .numeric(numeric), type: type)
        let frame = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            try parameter.encode(into: &writer)
        }
        var reader = DatabaseWireReader(frame)
        #expect(try QueryParameter(from: &reader) == parameter)
        try reader.ensureFullyRead()
        let literal = Literal.queryValue(.numeric(numeric), type: type)
        let encoded = try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in
            try QueryIRLiteralWireCodec.encode(literal, into: &writer)
        }
        #expect(encoded[0] == 18)
        var literalReader = DatabaseWireReader(encoded)
        #expect(try QueryIRLiteralWireCodec.decode(from: &literalReader) == literal)
        try literalReader.ensureFullyRead()
    }
}
