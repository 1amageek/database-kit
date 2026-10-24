import DatabaseKit
import DatabaseTypes
@testable import DatabaseWire
import Testing

@Suite("IR-centered query execution contracts")
struct QueryExecutionContractTests {
    @Test("Text, statement and block inputs retain their semantic owner")
    func inputRoundTrips() throws {
        #expect(throws: QueryExecutionOptionsError.pageSizeMustBePositive) {
            try QueryExecutionOptions(pageSize: 0).validate()
        }
        try QueryExecutionOptions(pageSize: 1).validate()
        let hostile = "Robert'); DROP TABLE items; --"
        let sql: SQL = try "SELECT \(hostile), \(Int32(42)), \(nil as String?)"
        #expect(sql.text == "SELECT $1, $2, $3")
        #expect(sql.parameters.map(\.position) == [1, 2, 3])
        #expect(sql.parameters.map(\.value) == [.primitive(.string(hostile)),
            .primitive(.int32(42)), .primitive(.null)])
        #expect(SQL(text: sql.text, parameters: sql.parameters) == sql)
        let statement = QueryStatement.select(SelectQuery(
            projection: [.expression(.parameter(position: 1), alias: "amount")],
            source: .values([])))
        let block = try SQLBlock(steps: [.statement(statement), .setting(.show(nil))])
        for input in [QueryInput.sql("SELECT $1 AS amount"), .statement(statement), .block(block)] {
            let request = QueryExecuteOperation.Request(input: input,
                parameters: [.init(position: 1, value: .primitive(.int32(42)))])
            let bytes: ByteString
            #if DATABASE_KIT_MULTI_BASE
            bytes = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute,
                requestID: 77, target: .database, request: request)
            #else
            bytes = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute,
                requestID: 77, request: request)
            #endif
            let decoded = try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: bytes)
            #expect(decoded.request.input == input)
            #expect(decoded.request.parameters == request.parameters)
        }
    }

    @Test("A common result retains exact values, duplicate labels and lazy frame ownership")
    func retainedRows() async throws {
        let numeric = try QueryNumericValue(value: .init(coefficient: 125, scale: 2), displayScale: 4)
        let columns = try [QueryColumn(number: 1, name: "value", type: .sql(.decimal(precision: nil, scale: nil)), isNullable: true),
            QueryColumn(number: 2, name: "value", type: .primitive(.int32), isNullable: true)]
        let metadata = try FieldObject([("source", .string("table"))])
        let expected = QueryRow(values: [.numeric(numeric), .primitive(.null)],
            annotations: metadata, version: [1, 2, 3])
        let page = try QueryRowPage(columns: columns, rows: [expected],
            affectedRows: 7, metadata: metadata)
        let frame = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute,
            requestID: 77, response: .rows(page))
        guard case .success(.rows(let retained)) = try DatabaseWireDecoder().decodeResponse(
            DatabaseOperationCatalog.queryExecute, from: frame, matching: 77) else {
            Issue.record("Expected retained row result")
            return
        }
        let result = QueryResult<QueryRowPage, RDFGraphPage, Bool>.rows(retained)
        guard case .rows(let rows) = result else {
            Issue.record("Result changed kinds")
            return
        }
        #expect(rows.columns == columns)
        #expect(rows.affectedRows == 7 && rows.metadata == metadata)
        var iterator = rows.makeAsyncIterator()
        #expect(try await iterator.next() == expected)
        #expect(try await iterator.next() == nil)
    }

    @Test("Blocks preserve statement kinds and command counts rather than flattening rows")
    func orderedOutcomes() throws {
        typealias Result = QueryResult<QueryRowPage, RDFGraphPage, Bool>
        let result = try Result(results: [.command(.update, affectedRows: 2),
            .boolean(true), .copy(bytes: [0, 255], affectedRows: 1)])
        #expect(result.results.count == 3)
        guard case .command(.update, let count) = result.results[0],
              case .boolean(true) = result.results[1],
              case .copy(let bytes, let copied) = result.results[2] else {
            Issue.record("Ordered statement outcomes changed")
            return
        }
        #expect(count == 2 && copied == 1 && bytes == [0, 255])
        #expect(result.results[0].command == .update)
        #expect(result.results[0].affectedRows == 2)
        #expect(result.results[0].rows.rowCount == 0)
        #expect(result.results[0].columns.isEmpty)
    }

    @Test("An empty or nested block is rejected rather than converted into success")
    func invalidOutcomes() {
        typealias Result = QueryResult<QueryRowPage, RDFGraphPage, Bool>
        #expect(throws: QueryResultError.emptyBlock) { try Result(results: []) }
        #expect(throws: QueryResultError.nestedBlock) {
            try Result(results: [.block([.command(.commit, affectedRows: nil)])])
        }
    }
    @Test("Text and IR retain their representations with one canonical response contract")
    func unifiedRowPayload() throws {
        let columns = [try QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: true)]
        let row = QueryRow(values: [.primitive(.int32(42))])
        let response = QueryExecuteOperation.Response.rows(try QueryRowPage(columns: columns, rows: [row]))
        let inputs: [QueryInput] = [.sql("SELECT 42 AS x"), .statement(.select(SelectQuery(
            projection: [.expression(.literal(.queryValue(.primitive(.int32(42)), type: .sql(.integer))), alias: "x")],
            source: .values([[]]))))]
        for input in inputs {
            let request = QueryExecuteOperation.Request(input: input)
            let frame = try DatabaseWireEncoder().encodeTestDatabaseRequest(DatabaseOperationCatalog.queryExecute,
                requestID: 77, request: request)
            #expect(try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame).request == request)
            let encoded = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute,
                requestID: 77, response: response)
            guard case .rows(let decoded) = try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute,
                from: encoded, matching: 77).get() else { Issue.record("Expected canonical rows"); return }
            var iterator = decoded.makeRowIterator()
            #expect(decoded.columns == columns)
            #expect(try iterator.next() == row)
        }
    }

}
