import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Persisted model")
struct PersistedModelTests {
    @Test("Concrete model crosses the heterogeneous boundary once")
    func concreteModelRoundTrip() throws {
        let source = PersistableFieldEncoderTestDocument(
            title: "Canonical",
            externalID: DatabaseTypes.UUID(high: 1, low: 2),
            occurredAt: try Timestamp(
                secondsSinceUnixEpoch: 1_721_234_567,
                nanoseconds: 125_000_000
            ),
            values: [1, 2, 3]
        )

        let persisted = try PersistedModel(source)
        let decoded = try persisted.decode(
            as: PersistableFieldEncoderTestDocument.self
        )

        #expect(persisted.entity == PersistableFieldEncoderTestDocument.persistableType)
        #expect(persisted.value(forFieldNamed: "title") == .string("Canonical"))
        #expect(decoded.id == source.id)
        #expect(decoded.title == source.title)
        #expect(decoded.values == source.values)
    }

    @Test("Duplicate field names are rejected")
    func duplicateFieldName() throws {
        let first = try PersistableField(number: 1, name: "id", value: .string("1"))
        let duplicate = try PersistableField(number: 2, name: "id", value: .string("2"))

        #expect(throws: PersistedModelError.duplicateFieldName("id")) {
            try PersistedModel(entity: "Event", fields: [first, duplicate])
        }
    }

    @Test("Duplicate field numbers are rejected")
    func duplicateFieldNumber() throws {
        let first = try PersistableField(number: 1, name: "id", value: .string("1"))
        let duplicate = try PersistableField(number: 1, name: "title", value: .string("Title"))

        #expect(throws: PersistedModelError.duplicateFieldNumber(1)) {
            try PersistedModel(entity: "Event", fields: [first, duplicate])
        }
    }
}
