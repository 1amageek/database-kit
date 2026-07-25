import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Persistable field encoding")
struct PersistableFieldEncoderTests {
    @Test("Generated traversal writes typed values directly to its destination")
    func generatedTraversalUsesConcreteOutput() throws {
        let document = PersistableFieldEncoderTestDocument(
            title: "Typed output",
            externalID: DatabaseTypes.UUID(high: 1, low: 2),
            occurredAt: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 125_000_000
            ),
            values: [1, 2, 3]
        )
        var output = FieldIdentityOutput()

        try document.encodePersistedFields(to: &output)

        #expect(output.identities == [
            FieldIdentity(name: "id", number: 1),
            FieldIdentity(name: "title", number: 2),
            FieldIdentity(name: "externalID", number: 3),
            FieldIdentity(name: "occurredAt", number: 4),
            FieldIdentity(name: "note", number: 5),
            FieldIdentity(name: "values", number: 6),
        ])
    }

    @Test("Schema identity lookup materializes only the selected field")
    func schemaIdentityLookup() throws {
        let document = PersistableFieldEncoderTestDocument(
            title: "Selected",
            externalID: DatabaseTypes.UUID(high: 1, low: 2),
            occurredAt: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 125_000_000
            ),
            note: nil,
            values: [1, 2, 3]
        )

        #expect(
            try document.persistedFieldValue(
                for: PersistableFieldEncoderTestDocument.fields.title.identity
            ) == .string("Selected")
        )
        #expect(
            try document.persistedFieldValue(
                for: PersistableFieldEncoderTestDocument.fields.note.identity
            ) == .null
        )
        #expect(
            try document.persistedFieldValue(
                for: FieldIdentity(name: "unknown", number: 100)
            ) == nil
        )
    }

    @Test("Schema identity lookup rejects mismatched names and numbers")
    func schemaIdentityMismatchFails() throws {
        let document = PersistableFieldEncoderTestDocument(
            title: "Mismatch",
            externalID: DatabaseTypes.UUID(high: 1, low: 2),
            occurredAt: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 125_000_000
            ),
            values: []
        )
        let title = PersistableFieldEncoderTestDocument.fields.title.identity

        #expect(
            throws: PersistableEncodingError.invalidSchema(
                entity: PersistableFieldEncoderTestDocument.persistableType,
                reason: "field identity 'other#\(title.number)' does not match 'title#\(title.number)'"
            )
        ) {
            try document.persistedFieldValue(
                for: FieldIdentity(
                    name: "other",
                    number: title.number
                )
            )
        }
    }

    @Test("Compiled documents round-trip without JSON")
    func compiledDocumentRoundTrip() throws {
        let externalID = DatabaseTypes.UUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )
        let occurredAt = try Timestamp(
            secondsSinceUnixEpoch: 1_721_234_567,
            nanoseconds: 125_000_000
        )
        let document = PersistableFieldEncoderTestDocument(
            title: "Runtime",
            externalID: externalID,
            occurredAt: occurredAt,
            values: [1, 4, 9]
        )

        let fields = try PersistableFieldEncoder.encode(document)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })

        #expect(byName["externalID"] == .uuid(DatabaseTypes.UUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )))
        #expect(byName["note"] == .null)
        #expect(byName["values"] == .array([.uint32(1), .uint32(4), .uint32(9)]))

        let decoded = try PersistableFieldEncoderTestDocument.decodePersistedFields(fields)
        #expect(decoded.id == document.id)
        #expect(decoded.title == document.title)
        #expect(decoded.externalID == externalID)
        #expect(decoded.occurredAt == occurredAt)
        #expect(decoded.note == nil)
        #expect(decoded.values == document.values)
    }

    @Test("Nested values round-trip as canonical objects")
    func nestedValueRoundTrip() throws {
        let current = PersistableFieldNestedValue(label: "current", priority: 2)
        let history = [
            PersistableFieldNestedValue(label: "created", priority: 0),
            PersistableFieldNestedValue(label: "updated", priority: 1),
        ]
        let document = PersistableFieldNestedTestDocument(value: current, history: history)

        let fields = try PersistableFieldEncoder.encode(document)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
        guard case .object = byName["value"] else {
            Issue.record("Nested value must use FieldValue.object")
            return
        }
        guard case .array(let encodedHistory) = byName["history"] else {
            Issue.record("Nested collection must use FieldValue.array")
            return
        }
        #expect(encodedHistory.count == history.count)
        #expect(encodedHistory.allSatisfy {
            if case .object = $0 { return true }
            return false
        })

        let decoded = try PersistableFieldNestedTestDocument.decodePersistedFields(fields)
        #expect(decoded.value == current)
        #expect(decoded.history == history)
    }

    @Test("Enum schema and values use the static field contract")
    func enumRoundTrip() throws {
        let document = PersistableEnumTestDocument(status: .active)

        #expect(PersistableEnumTestDocument.fields.status.type == .enum)
        #expect(
            PersistableEnumTestDocument.enumMetadata(for: "status")
                == EnumMetadata(
                    typeName: "PersistableTestStatus",
                    cases: ["active", "inactive"]
                )
        )

        let fields = try PersistableFieldEncoder.encode(document)
        #expect(fields.last?.value == .string("active"))
        let decoded = try PersistableEnumTestDocument.decodePersistedFields(fields)
        #expect(decoded.status == .active)
    }

    @Test("Every primitive field type has one consistent persistence contract")
    func primitiveFieldRoundTrip() throws {
        let date = try CivilDate(year: 2026, month: 7, day: 24)
        let time = try CivilTime(
            hour: 14,
            minute: 35,
            second: 12,
            nanoseconds: 345_678_901
        )
        let point = try GeographicPoint(latitude: 35.681_236, longitude: 139.767_125)
        let reference = try EntityReference(
            entity: "Event",
            id: .string("event-1"),
            partitions: FieldObject([
                (key: "calendar", value: .string("primary"))
            ])
        )
        let document = PersistablePrimitiveTestDocument(
            decimal: ExactDecimal(coefficient: 123_456, scale: 3),
            bytes: ByteString([0, 1, 2, 255]),
            date: date,
            time: time,
            dateTime: CivilDateTime(date: date, time: time),
            timestamp: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 123_456_789
            ),
            timeSpan: try TimeSpan(seconds: -2, nanoseconds: 500_000_000),
            calendarPeriod: CalendarPeriod(months: 14, days: 3),
            geographicPoint: point,
            geographicPosition: try GeographicPosition(
                point: point,
                ellipsoidalHeightInMeters: 42.5
            ),
            vector: try DatabaseTypes.Vector(float32: [1.25, -2.5, 3.75]),
            uuid: DatabaseTypes.UUID(
                high: 0x0011_2233_4455_6677,
                low: 0x8899_AABB_CCDD_EEFF
            ),
            object: try FieldObject([
                (key: "enabled", value: .bool(true)),
                (key: "priority", value: .int16(7))
            ]),
            reference: reference,
            rdfTerm: try RDFTerm.iri(validating: "https://example.com/event/1")
        )

        #expect(
            PersistablePrimitiveTestDocument.fieldSchemas.map(\.type) == [
                .string,
                .decimal,
                .bytes,
                .date,
                .time,
                .dateTime,
                .timestamp,
                .timeSpan,
                .calendarPeriod,
                .geographicPoint,
                .geographicPosition,
                .vector,
                .uuid,
                .object,
                .reference,
                .rdfTerm,
            ]
        )

        let fields = try PersistableFieldEncoder.encode(document)
        let decoded = try PersistablePrimitiveTestDocument.decodePersistedFields(fields)

        #expect(decoded.decimal == document.decimal)
        #expect(decoded.bytes == document.bytes)
        #expect(decoded.date == document.date)
        #expect(decoded.time == document.time)
        #expect(decoded.dateTime == document.dateTime)
        #expect(decoded.timestamp == document.timestamp)
        #expect(decoded.timeSpan == document.timeSpan)
        #expect(decoded.calendarPeriod == document.calendarPeriod)
        #expect(decoded.geographicPoint == document.geographicPoint)
        #expect(decoded.geographicPosition == document.geographicPosition)
        #expect(decoded.vector == document.vector)
        #expect(decoded.uuid == document.uuid)
        #expect(decoded.object == document.object)
        #expect(decoded.reference == document.reference)
        #expect(decoded.rdfTerm == document.rdfTerm)
    }

    @Test("Timestamp uses the absolute timestamp schema")
    func timestampUsesTimestampSchema() throws {
        let occurredAtSchema = try #require(
            PersistableFieldEncoderTestDocument.fieldSchemas.first {
                $0.name == "occurredAt"
            }
        )
        #expect(occurredAtSchema.type == .timestamp)

        let externalID = DatabaseTypes.UUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )
        let document = PersistableFieldEncoderTestDocument(
            title: "Timestamp",
            externalID: externalID,
            occurredAt: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 125_000_000
            ),
            values: []
        )
        let field = try #require(
            PersistableFieldEncoder.encode(document).first {
                $0.name == "occurredAt"
            }
        )
        guard case .timestamp = field.value else {
            Issue.record("Timestamp must persist as FieldValue.timestamp")
            return
        }
    }
}

private struct FieldIdentityOutput: PersistedFieldOutput {
    typealias Failure = Never

    private(set) var identities: [FieldIdentity] = []

    mutating func write<Value: FieldValueEncodable>(
        _ identity: FieldIdentity,
        value: borrowing Value,
        entity: String
    ) throws(PersistableEncodingFailure<Never>) {
        identities.append(identity)
    }
}

private enum PersistableTestStatus: String, PersistableEnum {
    case active
    case inactive
}

@Persistable
private struct PersistableEnumTestDocument {
    var id: String = "enum-fixture"
    var status: PersistableTestStatus
}
