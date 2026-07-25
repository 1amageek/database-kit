import DatabaseKit
import DatabaseTypes
@testable import DatabaseWire
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
        let frame = try EnvelopeWireFormat.encode(
            request: DatabaseWireRequestEnvelope(
                requestID: 0x0102_0304_0506_0708,
                operation: .queryExecute,
                payload: ByteString(
                    [UInt8](repeating: 0xa5, count: payloadByteCount)
                )
            ),
            limits: limits
        )

        let header = try EnvelopeWireFormat.decodeRequestHeader(frame)

        #expect(header.requestID == 0x0102_0304_0506_0708)
        #expect(header.operation == .queryExecute)
        #expect(throws: DatabaseWireError.self) {
            _ = try EnvelopeWireFormat.decodeRequest(frame)
        }
    }

    @Test("fixed response header validates message direction")
    func responseHeaderValidatesMessageDirection() throws {
        let request = try EnvelopeWireFormat.encode(
            request: DatabaseWireRequestEnvelope(
                requestID: 7,
                operation: .capabilitiesDescribe,
                payload: []
            )
        )

        #expect(
            throws: DatabaseWireError.invalidMessageKind(2)
        ) {
            _ = try EnvelopeWireFormat.decodeResponseHeader(request)
        }
    }

    @Test("request envelope matches the canonical golden vector")
    func requestEnvelopeMatchesGoldenVector() throws {
        let request = DatabaseWireRequestEnvelope(
            requestID: 0x0102_0304_0506_0708,
            operation: .capabilitiesDescribe,
            payload: []
        )

        let encoded = try EnvelopeWireFormat.encode(request: request)

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
        #expect(try EnvelopeWireFormat.decodeRequest(encoded) == request)
    }

    @Test("FieldValue preserves every canonical value family")
    func fieldValueRoundTrips() throws {
        let identity = try EntityReference(
            entity: "Event",
            id: .composite([
                .int8(-1),
                .int16(-2),
                .int32(-3),
                .int64(-4),
                .uint8(1),
                .uint16(2),
                .uint32(3),
                .uint64(4),
                .string("event-1"),
            ]),
            partitions: try FieldObject([
                (key: "snapshot", value: .string("snapshot-a")),
            ])
        )
        let value = FieldValue.object(
            try FieldObject([
                (key: "null", value: .null),
                (key: "bool", value: .bool(true)),
                (key: "signed", value: .int64(-42)),
                (key: "unsigned", value: .uint64(42)),
                (key: "float64", value: .float64(4.25)),
                (
                    key: "decimal",
                    value: .decimal(
                        ExactDecimal(coefficient: 12345, scale: 2)
                    )
                ),
                (key: "string", value: .string("calendar")),
                (key: "bytes", value: .bytes([0, 1, 2])),
                (
                    key: "date",
                    value: .date(
                        CivilDate(year: 2026, month: 7, day: 16)
                    )
                ),
                (
                    key: "time",
                    value: .time(
                        try CivilTime(
                            hour: 12,
                            minute: 34,
                            second: 56,
                            nanoseconds: 789
                        )
                    )
                ),
                (
                    key: "dateTime",
                    value: .dateTime(
                        CivilDateTime(
                            date: CivilDate(
                                year: 2026,
                                month: 7,
                                day: 16
                            ),
                            time: try CivilTime(
                                hour: 12,
                                minute: 34,
                                second: 56,
                                nanoseconds: 789
                            )
                        )
                    )
                ),
                (
                    key: "timestamp",
                    value: .timestamp(
                        try Timestamp(
                            secondsSinceUnixEpoch: 1_784_131_200,
                            nanoseconds: 123
                        )
                    )
                ),
                (
                    key: "timeSpan",
                    value: .timeSpan(
                        try TimeSpan(seconds: -2, nanoseconds: 500_000_000)
                    )
                ),
                (
                    key: "calendarPeriod",
                    value: .calendarPeriod(
                        CalendarPeriod(months: 14, days: 3)
                    )
                ),
                (
                    key: "geographicPoint",
                    value: .geographicPoint(
                        try GeographicPoint(
                            latitude: 35.681_236,
                            longitude: 139.767_125
                        )
                    )
                ),
                (
                    key: "geographicPosition",
                    value: .geographicPosition(
                        try GeographicPosition(
                            latitude: 35.681_236,
                            longitude: 139.767_125,
                            ellipsoidalHeightInMeters: 42.5
                        )
                    )
                ),
                (
                    key: "vector",
                    value: .vector(
                        try Vector(float32: [1.25, -2.5, 3.75])
                    )
                ),
                (
                    key: "array",
                    value: .array([.string("a"), .int64(1)])
                ),
                (key: "reference", value: .reference(identity)),
                (
                    key: "rdf",
                    value: .rdfTerm(
                        .literal(
                            RDFLiteral(
                                lexicalForm: "東京",
                                language: try RDFLanguageTag("ja")
                            )
                        )
                    )
                ),
                (
                    key: "uuid",
                    value: .uuid(
                        DatabaseTypes.UUID(
                            high: 0x0011_2233_4455_6677,
                            low: 0x8899_AABB_CCDD_EEFF
                        )
                    )
                ),
                (
                    key: "fixedWidthNumbers",
                    value: .array([
                        .int8(-8),
                        .int16(-16),
                        .int32(-32),
                        .int64(-64),
                        .uint8(8),
                        .uint16(16),
                        .uint32(32),
                        .uint64(64),
                        .float32(3.25),
                        .float64(6.5),
                    ])
                ),
            ])
        )
        let bytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try value.encode(into: &writer)
        }
        var reader = DatabaseWireReader(bytes)

        #expect(try FieldValue(from: &reader) == value)
        try reader.ensureFullyRead()

        var validationReader = DatabaseWireReader(bytes)
        try FieldValueWireValidator.validateValue(from: &validationReader)
        try validationReader.ensureFullyRead()
    }

    @Test("language-tag spelling has one canonical wire representation")
    func languageTagWireCanonicalization() throws {
        let uppercase = RDFTerm.literal(RDFLiteral(
            lexicalForm: "hello",
            language: try RDFLanguageTag("EN-Latn-US")
        ))
        let lowercase = RDFTerm.literal(RDFLiteral(
            lexicalForm: "hello",
            language: try RDFLanguageTag("en-latn-us")
        ))
        let uppercaseBytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try uppercase.encode(into: &writer)
        }
        let lowercaseBytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try lowercase.encode(into: &writer)
        }

        #expect(uppercaseBytes == lowercaseBytes)
    }

    @Test("DatabaseTypes.UUID has a stable canonical representation")
    func databaseUUIDCanonicalRepresentation() {
        let uuid = DatabaseTypes.UUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )

        #expect(uuid.description == "00112233-4455-6677-8899-aabbccddeeff")
        #expect(DatabaseTypes.UUID(bytes: uuid.bytes) == uuid)
        #expect(DatabaseTypes.UUID(bytes: [0]) == nil)
    }

    @Test("query result variants round-trip deterministically")
    func queryResultsRoundTrip() throws {
        let results: [QueryExecuteOperation.Response] = [
            .rows(
                try QueryRowPage(
                    columns: [
                        .init(number: 1, name: "title"),
                    ],
                    rows: [
                        QueryRow(
                            values: [.string("Event")],
                            version: [0x01, 0x02]
                        ),
                    ],
                    continuation: [1, 2, 3],
                    snapshotVersion: 12
                )
            ),
            .boolean(true),
            .rdfGraph(
                RDFGraphPage(
                    quads: [
                        RDFQuad(
                            subject: .iri(try RDFIRI("urn:event:1")),
                            predicate: RDFPredicateIRI(
                                try RDFIRI("urn:calendar:startsAt")
                            ),
                            object: .literal(
                                RDFLiteral(
                                    lexicalForm: "2026-07-16",
                                    datatype: XSDDatatype.date
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
            let encoded = try EnvelopeWireFormat.encode(result)
            let decoded = try EnvelopeWireFormat.decode(
                QueryExecuteOperation.Response.self,
                from: encoded
            )
            switch (result, decoded) {
            case (.boolean(let expected), .boolean(let actual)):
                #expect(actual == expected)
            case (.rows(let expected), .rows(let actual)):
                #expect(actual.columns == expected.columns)
                #expect(actual.rowCount == expected.rowCount)
                #expect(actual.continuation == expected.continuation)
                #expect(actual.snapshotVersion == expected.snapshotVersion)
                #expect(
                    try actual.materializedRows(maximumCount: 10)
                        == expected.materializedRows(maximumCount: 10)
                )
            case (.rdfGraph(let expected), .rdfGraph(let actual)):
                #expect(actual.quadCount == expected.quadCount)
                #expect(actual.continuation == expected.continuation)
                #expect(actual.snapshotVersion == expected.snapshotVersion)
                #expect(
                    try actual.materializedQuads(maximumCount: 10)
                        == expected.materializedQuads(maximumCount: 10)
                )
            default:
                Issue.record("Query result kind changed during round-trip")
            }
        }
    }

    @Test("mutation requests and typed result families round-trip")
    func mutationFamiliesRoundTrip() throws {
        let identity = try EntityReference(
            entity: "Event",
            id: .string("event-1")
        )
        let request = MutationExecuteOperation.Request(
            input: .entities([
                MutationExecuteOperation.Change(
                    kind: .update,
                    identity: identity,
                    fields: try FieldObject([
                        (key: "title", value: .string("Updated")),
                    ])
                ),
            ]),
            preconditions: [.mustExist(identity)],
            graphPartitions: try FieldObject([
                (key: "calendar", value: .string("primary")),
            ])
        )
        let recordResponse = MutationExecuteOperation.Response(
            commitVersion: 4,
            result: .entities([
                MutationExecuteOperation.EntityEffect(
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
            let encoded = try EnvelopeWireFormat.encode(value)
            #expect(
                try EnvelopeWireFormat.decode(
                    MutationExecuteOperation.Response.self,
                    from: encoded
                ) == value
            )
        }
        let encodedRequest = try EnvelopeWireFormat.encode(request)
        #expect(
            try EnvelopeWireFormat.decode(
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
        var unsupportedVersion = try EnvelopeWireFormat.encode(
            request: request
        ).copyBytes()
        unsupportedVersion[4] = 2
        #expect(throws: DatabaseWireError.unsupportedProtocolVersionValue(2)) {
            _ = try EnvelopeWireFormat.decodeRequest(
                ByteString(unsupportedVersion)
            )
        }

        var unknownOperation = try EnvelopeWireFormat.encode(
            request: request
        ).copyBytes()
        unknownOperation[15] = 0xFF
        unknownOperation[16] = 0xFF
        #expect(throws: DatabaseWireError.invalidOperationIdentifier(0xFFFF)) {
            _ = try EnvelopeWireFormat.decodeRequest(
                ByteString(unknownOperation)
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

        let nested = FieldValue.array([.array([.array([.null])])])
        let bytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try nested.encode(into: &writer)
        }
        var nestedReader = DatabaseWireReader(bytes, limits: limits)
        #expect(throws: DatabaseWireError.nestingTooDeep(actual: 3, maximum: 2)) {
            _ = try FieldValue(from: &nestedReader)
        }
    }

    @Test("wire strings decode every canonical UTF-8 width")
    func wireStringsDecodeCanonicalUTF8() throws {
        let encodedStrings: [([UInt8], String)] = [
            ([], ""),
            ([0x00, 0x41, 0x7F], "\0A\u{7F}"),
            ([0xC2, 0x80, 0xDF, 0xBF], "\u{80}\u{7FF}"),
            ([0xE0, 0xA0, 0x80, 0xE6, 0x9D, 0xB1], "\u{800}東"),
            ([0xF0, 0x90, 0x80, 0x80, 0xF4, 0x8F, 0xBF, 0xBF],
             "\u{10000}\u{10FFFF}"),
        ]

        for (encoded, expected) in encodedStrings {
            var reader = DatabaseWireReader(lengthPrefixed(encoded))
            #expect(try reader.readString() == expected)
            try reader.ensureFullyRead()
        }
    }

    @Test("wire strings reject every noncanonical UTF-8 family")
    func wireStringsRejectInvalidUTF8() {
        let invalidStrings: [[UInt8]] = [
            [0x80],
            [0xC0, 0x80],
            [0xC2],
            [0xE0, 0x9F, 0xBF],
            [0xED, 0xA0, 0x80],
            [0xE2, 0x82],
            [0xF0, 0x8F, 0xBF, 0xBF],
            [0xF4, 0x90, 0x80, 0x80],
            [0xF0, 0x90, 0x80],
            [0xF5, 0x80, 0x80, 0x80],
        ]

        for encoded in invalidStrings {
            var reader = DatabaseWireReader(lengthPrefixed(encoded))
            #expect(throws: DatabaseWireError.invalidUTF8) {
                _ = try reader.readString()
            }
        }
    }

    @Test("encoder and decoder enforce identical value object budgets")
    func valueObjectBudgetsAreSymmetric() throws {
        let value = FieldValue.array([.null, .null])
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
        #expect(try FieldValue(from: &acceptedReader) == value)
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
            _ = try FieldValue(from: &rejectedReader)
        }
    }

    @Test("canonical RDF consumes the enclosing wire budget")
    func canonicalRDFUsesGlobalBudget() throws {
        let value = FieldValue.rdfTerm(.tripleTerm(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: try RDFPredicateIRI("urn:predicate"),
            object: .iri(try RDFIRI("urn:object"))
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
        #expect(try FieldValue(from: &acceptedReader) == value)

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
            _ = try FieldValue(from: &rejectedReader)
        }
    }

    @Test("typed remote failures survive the response envelope")
    func typedRemoteFailureRoundTrips() throws {
        let failure = RemoteOperationError(
            category: .conflict,
            code: "precondition_failed",
            message: "The active snapshot changed",
            retryability: .backoff,
            details: try FieldObject([
                (key: "actualVersion", value: .uint64(9)),
            ])
        )
        let response = DatabaseWireResponseEnvelope(
            requestID: 42,
            operation: .mutationExecute,
            payload: .failure(failure)
        )

        #expect(
            try EnvelopeWireFormat.decodeResponse(
                EnvelopeWireFormat.encode(response: response)
            ) == response
        )
    }

    private func lengthPrefixed(_ bytes: [UInt8]) -> [UInt8] {
        let count = UInt32(bytes.count)
        return [
            UInt8(truncatingIfNeeded: count),
            UInt8(truncatingIfNeeded: count >> 8),
            UInt8(truncatingIfNeeded: count >> 16),
            UInt8(truncatingIfNeeded: count >> 24),
        ] + bytes
    }
}
