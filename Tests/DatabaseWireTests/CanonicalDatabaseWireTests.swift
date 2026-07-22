import DatabaseValue
import DatabaseWire
import Testing

@Suite("Canonical DatabaseWire")
struct CanonicalDatabaseWireTests {
    @Test("fixed request header decoding does not traverse an oversized payload")
    func requestHeaderDecodingIsIndependentOfPayloadLimits() throws {
        let payloadByteCount = DatabaseWireLimits.default.maximumFrameBytes
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: payloadByteCount + 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: payloadByteCount,
            maximumCollectionCount: 1_024,
            maximumNestingDepth: 64,
            maximumObjectCount: 1_024
        )
        let frame = try DatabaseEnvelopeCodec.encode(
            request: DatabaseWireRequestEnvelope(
                requestID: 0x0102_0304_0506_0708,
                operation: .queryExecute,
                payload: DatabaseBytes(
                    [UInt8](repeating: 0xa5, count: payloadByteCount)
                )
            ),
            limits: limits
        )

        let header = try DatabaseEnvelopeCodec.decodeRequestHeader(frame)

        #expect(header.requestID == 0x0102_0304_0506_0708)
        #expect(header.operation == .queryExecute)
        #expect(throws: DatabaseWireError.self) {
            _ = try DatabaseEnvelopeCodec.decodeRequest(frame)
        }
    }

    @Test("fixed response header validates message direction")
    func responseHeaderValidatesMessageDirection() throws {
        let request = try DatabaseEnvelopeCodec.encode(
            request: DatabaseWireRequestEnvelope(
                requestID: 7,
                operation: .capabilitiesDescribe,
                payload: []
            )
        )

        #expect(
            throws: DatabaseWireError.invalidMessageKind(2)
        ) {
            _ = try DatabaseEnvelopeCodec.decodeResponseHeader(request)
        }
    }

    @Test("request envelope matches the canonical golden vector")
    func requestEnvelopeMatchesGoldenVector() throws {
        let request = DatabaseWireRequestEnvelope(
            requestID: 0x0102_0304_0506_0708,
            operation: .capabilitiesDescribe,
            payload: []
        )

        let encoded = try DatabaseEnvelopeCodec.encode(request: request)

        #expect(encoded == [
            0x44, 0x42, 0x57, 0x52,
            0x01, 0x00,
            0x01,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x01, 0x01,
            0x00,
            0x00,
            0x00, 0x00, 0x00, 0x00,
        ])
        #expect(try DatabaseEnvelopeCodec.decodeRequest(encoded) == request)
    }

    @Test("DatabaseValue preserves every canonical value family")
    func databaseValueRoundTrips() throws {
        let identity = RecordIdentity(
            entity: "Event",
            id: .composite([.string("event-1"), .uint64(7)]),
            partitions: [
                DatabaseObjectField(number: 1, name: "snapshot", value: .string("snapshot-a")),
            ]
        )
        let value = DatabaseValue.object([
            DatabaseObjectField(number: 1, name: "null", value: .null),
            DatabaseObjectField(number: 2, name: "bool", value: .bool(true)),
            DatabaseObjectField(number: 3, name: "signed", value: .int64(-42)),
            DatabaseObjectField(number: 4, name: "unsigned", value: .uint64(42)),
            DatabaseObjectField(number: 5, name: "double", value: .double(4.25)),
            DatabaseObjectField(number: 6, name: "decimal", value: .decimal(coefficient: 12345, scale: 2)),
            DatabaseObjectField(number: 7, name: "string", value: .string("calendar")),
            DatabaseObjectField(number: 8, name: "bytes", value: .bytes([0, 1, 2])),
            DatabaseObjectField(number: 9, name: "date", value: .date(DatabaseDate(year: 2026, month: 7, day: 16))),
            DatabaseObjectField(
                number: 10,
                name: "timestamp",
                value: .timestamp(DatabaseTimestamp(secondsSinceUnixEpoch: 1_784_131_200, nanoseconds: 123))
            ),
            DatabaseObjectField(number: 11, name: "array", value: .array([.string("a"), .int64(1)])),
            DatabaseObjectField(number: 12, name: "reference", value: .reference(identity)),
            DatabaseObjectField(
                number: 13,
                name: "rdf",
                value: .rdfTerm(
                    .literal(
                        DatabaseRDFLiteral(
                            lexicalForm: "東京",
                            language: try DatabaseRDFLanguageTag("ja")
                        )
                    )
                )
            ),
            DatabaseObjectField(
                number: 14,
                name: "uuid",
                value: .uuid(
                    DatabaseUUID(
                        high: 0x0011_2233_4455_6677,
                        low: 0x8899_AABB_CCDD_EEFF
                    )
                )
            ),
        ])
        var writer = DatabaseWireWriter()
        try value.encode(into: &writer)
        var reader = DatabaseWireReader(writer.bytes)

        #expect(try DatabaseValue(from: &reader) == value)
        try reader.ensureFullyRead()
    }

    @Test("language-tag spelling has one canonical wire representation")
    func languageTagWireCanonicalization() throws {
        let uppercase = DatabaseRDFTerm.literal(DatabaseRDFLiteral(
            lexicalForm: "hello",
            language: try DatabaseRDFLanguageTag("EN-Latn-US")
        ))
        let lowercase = DatabaseRDFTerm.literal(DatabaseRDFLiteral(
            lexicalForm: "hello",
            language: try DatabaseRDFLanguageTag("en-latn-us")
        ))
        var uppercaseWriter = DatabaseWireWriter()
        var lowercaseWriter = DatabaseWireWriter()

        try uppercase.encode(into: &uppercaseWriter)
        try lowercase.encode(into: &lowercaseWriter)

        #expect(uppercaseWriter.bytes == lowercaseWriter.bytes)
    }

    @Test("DatabaseUUID has a stable canonical representation")
    func databaseUUIDCanonicalRepresentation() {
        let uuid = DatabaseUUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )

        #expect(uuid.description == "00112233-4455-6677-8899-aabbccddeeff")
        #expect(DatabaseUUID(bytes: uuid.bytes) == uuid)
        #expect(DatabaseUUID(bytes: [0]) == nil)
    }

    @Test("query result variants round-trip deterministically")
    func queryResultsRoundTrip() throws {
        let results: [QueryExecuteOperation.Response] = [
            .rows(
                QueryExecuteOperation.RowPage(
                    rows: [
                        QueryExecuteOperation.Row(
                            values: [DatabaseObjectField(number: 1, name: "title", value: .string("Event"))],
                            version: [0x01, 0x02]
                        ),
                    ],
                    continuation: [1, 2, 3],
                    snapshotVersion: 12
                )
            ),
            .boolean(true),
            .rdfGraph(
                QueryExecuteOperation.GraphPage(
                    triples: [
                        try DatabaseRDFQuad(
                            subject: .iri("urn:event:1"),
                            predicate: .iri("urn:calendar:startsAt"),
                            object: .literal(
                                DatabaseRDFLiteral(
                                    lexicalForm: "2026-07-16",
                                    datatype: DatabaseXSDDatatype.date
                                        .typedLiteralDatatype
                                )
                            )
                        ),
                    ],
                    snapshotVersion: 27
                )
            ),
        ]

        for result in results {
            let encoded = try DatabaseEnvelopeCodec.encode(result)
            #expect(
                try DatabaseEnvelopeCodec.decode(
                    QueryExecuteOperation.Response.self,
                    from: encoded
                ) == result
            )
        }
    }

    @Test("mutation requests and typed result families round-trip")
    func mutationFamiliesRoundTrip() throws {
        let identity = RecordIdentity(
            entity: "Event",
            id: .string("event-1")
        )
        let request = MutationExecuteOperation.Request(
            input: .records([
                MutationExecuteOperation.Change(
                    kind: .update,
                    identity: identity,
                    fields: [
                        DatabaseObjectField(
                            number: 1,
                            name: "title",
                            value: .string("Updated")
                        ),
                    ]
                ),
            ]),
            preconditions: [.mustExist(identity)],
            graphPartitions: [
                DatabaseObjectField(
                    number: 1,
                    name: "calendar",
                    value: .string("primary")
                ),
            ]
        )
        let recordResponse = MutationExecuteOperation.Response(
            commitVersion: 4,
            result: .records([
                MutationExecuteOperation.RecordEffect(
                    kind: .update,
                    identity: identity,
                    version: [1, 2, 3]
                ),
            ])
        )
        let rdfResponse = MutationExecuteOperation.Response(
            commitVersion: 5,
            result: .rdf(
                MutationExecuteOperation.RDFEffect(
                    insertedQuads: 7,
                    deletedQuads: 3,
                    createdGraphs: 1,
                    droppedGraphs: 2
                )
            )
        )

        for value in [recordResponse, rdfResponse] {
            let encoded = try DatabaseEnvelopeCodec.encode(value)
            #expect(
                try DatabaseEnvelopeCodec.decode(
                    MutationExecuteOperation.Response.self,
                    from: encoded
                ) == value
            )
        }
        let encodedRequest = try DatabaseEnvelopeCodec.encode(request)
        #expect(
            try DatabaseEnvelopeCodec.decode(
                MutationExecuteOperation.Request.self,
                from: encodedRequest
            ) == request
        )
    }

    @Test("unknown versions and operation identifiers are rejected")
    func unknownHeaderValuesAreRejected() throws {
        let request = DatabaseWireRequestEnvelope(
            requestID: 1,
            operation: .capabilitiesDescribe,
            payload: []
        )
        var unsupportedVersion = try DatabaseEnvelopeCodec.encode(
            request: request
        ).copyBytes()
        unsupportedVersion[4] = 2
        #expect(throws: DatabaseWireError.unsupportedProtocolVersionValue(2)) {
            _ = try DatabaseEnvelopeCodec.decodeRequest(
                DatabaseBytes(unsupportedVersion)
            )
        }

        var unknownOperation = try DatabaseEnvelopeCodec.encode(
            request: request
        ).copyBytes()
        unknownOperation[15] = 0xFF
        unknownOperation[16] = 0xFF
        #expect(throws: DatabaseWireError.invalidOperationIdentifier(0xFFFF)) {
            _ = try DatabaseEnvelopeCodec.decodeRequest(
                DatabaseBytes(unknownOperation)
            )
        }
    }

    @Test("decoder budgets reject count and nesting bombs")
    func decoderBudgetsRejectHostileFrames() throws {
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 32,
            maximumByteStringBytes: 64,
            maximumCollectionCount: 2,
            maximumNestingDepth: 2,
            maximumObjectCount: 8
        )
        var countReader = DatabaseWireReader([3, 0, 0, 0], limits: limits)
        #expect(throws: DatabaseWireError.collectionTooLarge(actual: 3, maximum: 2)) {
            _ = try countReader.readCount()
        }

        let nested = DatabaseValue.array([.array([.array([.null])])])
        var writer = DatabaseWireWriter()
        try nested.encode(into: &writer)
        var nestedReader = DatabaseWireReader(writer.bytes, limits: limits)
        #expect(throws: DatabaseWireError.nestingTooDeep(actual: 3, maximum: 2)) {
            _ = try DatabaseValue(from: &nestedReader)
        }
    }

    @Test("encoder and decoder enforce identical value object budgets")
    func valueObjectBudgetsAreSymmetric() throws {
        let value = DatabaseValue.array([.null, .null])
        let acceptedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 32,
            maximumByteStringBytes: 64,
            maximumCollectionCount: 8,
            maximumNestingDepth: 2,
            maximumObjectCount: 5
        )
        let encoded = try DatabaseWireWriter.encode(
            limits: acceptedLimits
        ) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try value.encode(into: &writer)
        }
        var acceptedReader = DatabaseWireReader(
            encoded,
            limits: acceptedLimits
        )
        #expect(try DatabaseValue(from: &acceptedReader) == value)
        try acceptedReader.ensureFullyRead()

        let rejectedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 32,
            maximumByteStringBytes: 64,
            maximumCollectionCount: 8,
            maximumNestingDepth: 2,
            maximumObjectCount: 4
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try DatabaseWireWriter.encode(
                limits: rejectedLimits
            ) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
                try value.encode(into: &writer)
            }
        }

        var rejectedReader = DatabaseWireReader(
            encoded,
            limits: rejectedLimits
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try DatabaseValue(from: &rejectedReader)
        }
    }

    @Test("canonical RDF consumes the enclosing wire budget")
    func canonicalRDFUsesGlobalBudget() throws {
        let value = DatabaseValue.rdfTerm(.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .iri("urn:predicate"),
            object: .iri("urn:object")
        ))
        let acceptedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 128,
            maximumByteStringBytes: 512,
            maximumCollectionCount: 8,
            maximumNestingDepth: 2,
            maximumObjectCount: 5
        )
        let encoded = try DatabaseWireWriter.encode(
            limits: acceptedLimits
        ) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try value.encode(into: &writer)
        }
        var acceptedReader = DatabaseWireReader(
            encoded,
            limits: acceptedLimits
        )
        #expect(try DatabaseValue(from: &acceptedReader) == value)

        let rejectedLimits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 128,
            maximumByteStringBytes: 512,
            maximumCollectionCount: 8,
            maximumNestingDepth: 2,
            maximumObjectCount: 4
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try DatabaseWireWriter.encode(
                limits: rejectedLimits
            ) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
                try value.encode(into: &writer)
            }
        }
        var rejectedReader = DatabaseWireReader(
            encoded,
            limits: rejectedLimits
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 5,
                maximum: 4
            )
        ) {
            _ = try DatabaseValue(from: &rejectedReader)
        }
    }

    @Test("typed remote failures survive the response envelope")
    func typedRemoteFailureRoundTrips() throws {
        let failure = DatabaseRemoteError(
            category: .conflict,
            code: "precondition_failed",
            message: "The active snapshot changed",
            retryability: .backoff,
            details: [DatabaseObjectField(number: 1, name: "actualVersion", value: .uint64(9))]
        )
        let response = DatabaseWireResponseEnvelope(
            requestID: 42,
            operation: .mutationExecute,
            payload: .failure(failure)
        )

        #expect(
            try DatabaseEnvelopeCodec.decodeResponse(
                DatabaseEnvelopeCodec.encode(response: response)
            ) == response
        )
    }
}
