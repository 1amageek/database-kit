import Testing
import DatabaseWire

@Suite("Database Wire Tests")
struct DatabaseWireTests {
    @Test func schemaRoundTripsWithoutFoundationCodable() throws {
        let schema = DatabaseWireSchema(
            entities: [
                DatabaseWireEntitySchema(
                    typeName: "Article",
                    version: 1,
                    fields: [
                        DatabaseWireFieldSchema(
                            name: "title",
                            type: .string,
                            isOptional: false,
                            fieldNumber: 1
                        ),
                        DatabaseWireFieldSchema(
                            name: "publishedAt",
                            type: .int64,
                            isOptional: true,
                            fieldNumber: 2
                        ),
                        DatabaseWireFieldSchema(
                            name: "score",
                            type: .double,
                            isOptional: true,
                            fieldNumber: 3
                        ),
                        DatabaseWireFieldSchema(
                            name: "metadata",
                            type: .object,
                            isOptional: true,
                            fieldNumber: 4
                        ),
                        DatabaseWireFieldSchema(
                            name: "owner",
                            type: .reference,
                            isOptional: true,
                            fieldNumber: 5
                        )
                    ],
                    indexes: [
                        DatabaseWireIndexDescriptor(
                            name: "byTitle",
                            kind: .scalar,
                            fields: ["title"]
                        ),
                        DatabaseWireIndexDescriptor(
                            name: "byEmbedding",
                            kind: .vector,
                            fields: ["embedding"],
                            parameters: [
                                DatabaseWireNamedValue(name: "dimensions", value: .int64(3)),
                                DatabaseWireNamedValue(name: "metric", value: .string("cosine"))
                            ]
                        )
                    ]
                )
            ]
        )

        let decoded = try DatabaseWireCodec.decodeSchema(
            DatabaseWireCodec.encode(schema: schema)
        )

        #expect(decoded == schema)
    }

    @Test func recordRoundTripsFieldValues() throws {
        let record = DatabaseWireRecord(
            typeName: "Article",
            id: "article-1",
            fields: [
                DatabaseWireNamedValue(name: "title", value: .string("Hello")),
                DatabaseWireNamedValue(name: "tags", value: .array([.string("swift"), .string("wire")])),
                DatabaseWireNamedValue(name: "score", value: .double(42.5)),
                DatabaseWireNamedValue(name: "payload", value: .bytes([0x01, 0x02])),
                DatabaseWireNamedValue(
                    name: "metadata",
                    value: .object([
                        DatabaseWireNamedValue(name: "owner", value: .reference("user-1"))
                    ])
                )
            ]
        )

        let decoded = try DatabaseWireCodec.decodeRecord(
            DatabaseWireCodec.encode(record: record)
        )

        #expect(decoded == record)
    }

    @Test func fieldTypesAndFieldValuesRoundTripWithoutRepresentationGaps() throws {
        let typeSamples: [(DatabaseWireFieldType, DatabaseWireFieldValue)] = [
            (.bool, .bool(true)),
            (.int64, .int64(-42)),
            (.double, .double(42.5)),
            (.string, .string("hello")),
            (.bytes, .bytes([0x01, 0x02])),
            (.array, .array([.string("swift"), .int64(6)])),
            (
                .object,
                .object([
                    DatabaseWireNamedValue(name: "enabled", value: .bool(true))
                ])
            ),
            (.reference, .reference("record-1"))
        ]

        for (fieldType, fieldValue) in typeSamples {
            var typeWriter = DatabaseWireBinaryWriter()
            fieldType.encode(into: &typeWriter)
            var typeReader = DatabaseWireBinaryReader(typeWriter.bytes)
            #expect(try DatabaseWireFieldType(from: &typeReader) == fieldType)
            try typeReader.ensureFullyRead()

            var valueWriter = DatabaseWireBinaryWriter()
            try fieldValue.encode(into: &valueWriter)
            var valueReader = DatabaseWireBinaryReader(valueWriter.bytes)
            #expect(try DatabaseWireFieldValue(from: &valueReader) == fieldValue)
            try valueReader.ensureFullyRead()
        }

        var nullWriter = DatabaseWireBinaryWriter()
        try DatabaseWireFieldValue.null.encode(into: &nullWriter)
        var nullReader = DatabaseWireBinaryReader(nullWriter.bytes)
        #expect(try DatabaseWireFieldValue(from: &nullReader) == .null)
        try nullReader.ensureFullyRead()
    }

    @Test func queryRoundTripsPredicateTree() throws {
        let query = DatabaseWireQueryRequest(
            typeName: "Article",
            predicate: .and([
                .comparison(field: "status", op: .equal, value: .string("published")),
                .not(.comparison(field: "archived", op: .equal, value: .bool(true)))
            ]),
            limit: 20
        )

        let decoded = try DatabaseWireCodec.decodeQuery(
            DatabaseWireCodec.encode(query: query)
        )

        #expect(decoded == query)
    }

    @Test func vectorQueryRoundTripsSearchParameters() throws {
        let query = DatabaseWireVectorQueryRequest(
            typeName: "Article",
            fieldName: "embedding",
            dimensions: 3,
            metric: .cosine,
            queryVector: [1, 0, 0],
            k: 2,
            predicate: .comparison(field: "status", op: .equal, value: .string("published"))
        )

        let decoded = try DatabaseWireCodec.decodeVectorQuery(
            DatabaseWireCodec.encode(vectorQuery: query)
        )

        #expect(decoded == query)
    }

    @Test func requestEnvelopeRoundTripsAllOperations() throws {
        let schema = DatabaseWireSchema(
            entities: [
                DatabaseWireEntitySchema(
                    typeName: "Article",
                    version: 1,
                    fields: [],
                    indexes: []
                )
            ]
        )
        let record = DatabaseWireRecord(
            typeName: "Article",
            id: "article-1",
            fields: [
                DatabaseWireNamedValue(name: "title", value: .string("Hello"))
            ]
        )
        let query = DatabaseWireQueryRequest(
            typeName: "Article",
            predicate: .comparison(field: "title", op: .equal, value: .string("Hello")),
            limit: 10
        )
        let vectorQuery = DatabaseWireVectorQueryRequest(
            typeName: "Article",
            fieldName: "embedding",
            dimensions: 3,
            metric: .cosine,
            queryVector: [1, 0, 0],
            k: 2
        )
        let requests: [DatabaseWireRequest] = [
            .applySchema(schema),
            .putRecord(record),
            .getRecord(typeName: "Article", id: "article-1"),
            .query(query),
            .vectorQuery(vectorQuery)
        ]

        for request in requests {
            let decoded = try DatabaseWireCodec.decodeRequest(
                DatabaseWireCodec.encode(request: request)
            )
            #expect(decoded == request)
        }
    }

    @Test func responseEnvelopeRoundTripsPayloadsAndFailures() throws {
        let record = DatabaseWireRecord(
            typeName: "Article",
            id: "article-1",
            fields: [
                DatabaseWireNamedValue(name: "title", value: .string("Hello"))
            ]
        )
        let responses: [DatabaseWireResponse] = [
            .empty,
            .record(nil),
            .record(record),
            .records([record]),
            .scoredRecords([DatabaseWireScoredRecord(record: record, distance: 0.25)]),
            .failure(status: .unsupported, message: "unsupported operation")
        ]

        for response in responses {
            let decoded = try DatabaseWireCodec.decodeResponse(
                DatabaseWireCodec.encode(response: response)
            )
            #expect(decoded == response)
        }
    }

    @Test func recordMapsToStableKeyValueOperation() throws {
        let record = DatabaseWireRecord(
            typeName: "Article",
            id: "article-1",
            fields: [
                DatabaseWireNamedValue(name: "title", value: .string("Hello"))
            ]
        )

        let operation = try DatabaseWireStorageBridge.recordSetOperation(record)

        guard case .set(let key, let value) = operation else {
            Issue.record("Expected record set operation")
            return
        }
        #expect(key == (try DatabaseWireStorageBridge.recordKey(entityName: "Article", id: "article-1")))
        #expect(try DatabaseWireStorageBridge.decodeRecordValue(value) == record)
    }

    @Test func queryPlanKeepsPredicateAsPostFilter() throws {
        let query = DatabaseWireQueryRequest(
            typeName: "Article",
            predicate: .comparison(field: "status", op: .equal, value: .string("published")),
            limit: 20
        )

        let plan = try DatabaseWireStorageBridge.queryPlan(query)
        let prefix = try DatabaseWireStorageBridge.recordPrefix(entityName: "Article")
        let firstKey = try DatabaseWireStorageBridge.recordKey(entityName: "Article", id: "a")
        let unrelatedKey = try DatabaseWireStorageBridge.recordKey(entityName: "Author", id: "a")

        guard case .range(let begin, let end, let limit, let reverse) = plan.operation else {
            Issue.record("Expected entity range operation")
            return
        }
        #expect(begin == prefix)
        #expect(limit == 0)
        #expect(reverse == false)
        #expect(plan.postFilter == query.predicate)
        #expect(plan.requiresPostFilter)
        #expect(lexicographicCompare(firstKey, begin) >= 0)
        #expect(lexicographicCompare(firstKey, end) < 0)
        #expect(!(lexicographicCompare(unrelatedKey, begin) >= 0 && lexicographicCompare(unrelatedKey, end) < 0))
    }

    @Test func queryOperationRejectsPredicateInsteadOfDroppingIt() throws {
        let query = DatabaseWireQueryRequest(
            typeName: "Article",
            predicate: .comparison(field: "status", op: .equal, value: .string("published")),
            limit: 20
        )

        #expect(throws: DatabaseWireError.unsupportedPredicatePlan) {
            _ = try DatabaseWireStorageBridge.queryOperation(query)
        }
    }

    @Test func predicateFreeQueryOperationMapsToEntityPrefixRangeOperation() throws {
        let query = DatabaseWireQueryRequest(typeName: "Article", predicate: nil, limit: 20)

        let operation = try DatabaseWireStorageBridge.queryOperation(query)
        let prefix = try DatabaseWireStorageBridge.recordPrefix(entityName: "Article")

        guard case .range(let begin, _, let limit, let reverse) = operation else {
            Issue.record("Expected entity range operation")
            return
        }
        #expect(begin == prefix)
        #expect(limit == 20)
        #expect(reverse == false)
    }

    @Test func trailingBytesAreRejected() throws {
        var encoded = try DatabaseWireCodec.encode(
            query: DatabaseWireQueryRequest(typeName: "Article", predicate: nil, limit: 1)
        )
        encoded.append(0xFF)

        #expect(throws: DatabaseWireError.self) {
            _ = try DatabaseWireCodec.decodeQuery(encoded)
        }
    }

    @Test func invalidUTF8StringIsRejected() throws {
        var writer = DatabaseWireBinaryWriter()
        try writer.writeBytes([0xFF])
        var reader = DatabaseWireBinaryReader(writer.bytes)

        #expect(throws: DatabaseWireError.self) {
            _ = try reader.readString()
        }
    }

    @Test func invalidBoolByteIsRejected() throws {
        var reader = DatabaseWireBinaryReader([0x02])

        #expect(throws: DatabaseWireError.self) {
            _ = try reader.readBool()
        }
    }

    @Test func countOverflowIsRejected() throws {
        var writer = DatabaseWireBinaryWriter()

        #expect(throws: DatabaseWireError.self) {
            try writer.writeCount(-1)
        }
        #expect(throws: DatabaseWireError.self) {
            try writer.writeCount(Int(UInt32.max) + 1)
        }
    }

    private func lexicographicCompare(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        let count = min(lhs.count, rhs.count)
        for index in 0..<count {
            if lhs[index] != rhs[index] {
                return lhs[index] < rhs[index] ? -1 : 1
            }
        }
        if lhs.count == rhs.count {
            return 0
        }
        return lhs.count < rhs.count ? -1 : 1
    }
}
