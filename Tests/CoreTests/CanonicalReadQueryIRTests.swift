import Testing
import Foundation
import QueryIR
import DatabaseClientProtocol
import Core

@Suite("Canonical Read QueryIR")
struct CanonicalReadQueryIRTests {
    @Test("QueryParameterValue preserves structured arrays and objects")
    func queryParameterValueRoundTrip() throws {
        let original = QueryParameterValue.object([
            "vector": .array([.double(0.1), .double(0.2), .double(0.3)]),
            "options": .object([
                "k": .int(10),
                "metric": .string("cosine"),
                "includeScores": .bool(true)
            ])
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryParameterValue.self, from: data)
        #expect(decoded == original)
    }

    @Test("SelectQuery with accessPath round-trips through QueryRequest")
    func canonicalQueryRequestRoundTrip() throws {
        let selectQuery = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            accessPath: .index(
                IndexScanSource(
                    indexName: "Document_vector_embedding",
                    kindIdentifier: "vector",
                    parameters: [
                        "fieldName": .string("embedding"),
                        "dimensions": .int(3),
                        "queryVector": .array([.double(0.1), .double(0.2), .double(0.3)]),
                        "k": .int(5),
                        "metric": .string("cosine")
                    ]
                )
            ),
            limit: 5
        )

        let original = QueryRequest(
            statement: .select(selectQuery),
            options: ReadExecutionOptions(
                consistency: .snapshot,
                pageSize: 20,
                continuation: QueryContinuation("cursor-token")
            ),
            partitionValues: ["tenantID": "tenant-1"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryRequest.self, from: data)

        guard case .select(let decodedSelectQuery) = decoded.statement else {
            Issue.record("Expected select statement")
            return
        }

        #expect(decodedSelectQuery == selectQuery)
        #expect(decoded.options.consistency == .snapshot)
        #expect(decoded.options.pageSize == 20)
        #expect(decoded.options.continuation?.token == "cursor-token")
        #expect(decoded.partitionValues == ["tenantID": "tenant-1"])
    }

    @Test("QueryResponse preserves row annotations and metadata")
    func canonicalQueryResponseRoundTrip() throws {
        let original = QueryResponse(
            rows: [
                QueryRow(
                    fields: ["id": .string("doc-1"), "title": .string("Vector Search")],
                    annotations: ["distance": .double(0.12), "rank": .int64(1)]
                )
            ],
            continuation: QueryContinuation("next-page"),
            metadata: [
                "fulltext.totalCount": .int64(42),
                "fulltext.facets.category": .array([
                    .array([.string("search"), .int64(10)]),
                    .array([.string("database"), .int64(8)])
                ])
            ],
            affectedRows: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QueryResponse.self, from: data)
        #expect(decoded.rows == original.rows)
        #expect(decoded.continuation == original.continuation)
        #expect(decoded.metadata == original.metadata)
    }

    @Test("SelectQuery replacing helpers preserve unrelated fields")
    func selectQueryReplacingHelpers() {
        let original = SelectQuery(
            projection: .all,
            source: .table(TableRef(table: "Document")),
            accessPath: .index(
                IndexScanSource(
                    indexName: "Document_vector_embedding",
                    kindIdentifier: "vector"
                )
            ),
            filter: .equal(.column(ColumnRef("status")), .literal(.string("active"))),
            orderBy: [SortKey(.column(ColumnRef("createdAt")))],
            limit: 20,
            offset: 10,
            distinct: true,
            subqueries: [NamedSubquery(name: "docs", query: SelectQuery(projection: .all, source: .table(TableRef(table: "Document"))))],
            reduced: true,
            from: ["graph-a"],
            fromNamed: ["graph-b"]
        )

        let updated = original
            .replacing(filter: .equal(.column(ColumnRef("status")), .literal(.string("archived"))))
            .replacing(orderBy: nil)
            .replacing(limit: 1)
            .replacing(offset: nil)

        #expect(updated.source == original.source)
        #expect(updated.accessPath == original.accessPath)
        #expect(updated.subqueries == original.subqueries)
        #expect(updated.from == original.from)
        #expect(updated.fromNamed == original.fromNamed)
        #expect(updated.distinct == original.distinct)
        #expect(updated.reduced == original.reduced)
        #expect(updated.orderBy == nil)
        #expect(updated.limit == 1)
        #expect(updated.offset == nil)

        guard case .equal(_, let rhs) = updated.filter else {
            Issue.record("Expected updated filter")
            return
        }
        #expect(rhs == .literal(.string("archived")))
    }
}
