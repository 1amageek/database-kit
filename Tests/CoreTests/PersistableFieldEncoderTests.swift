import Core
import DatabaseValue
import Foundation
import Testing

@Suite("Persistable field encoding")
struct PersistableFieldEncoderTests {
    @Test("Compiled documents round-trip without JSON")
    func compiledDocumentRoundTrip() throws {
        let externalID = try #require(
            UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")
        )
        let occurredAt = Date(timeIntervalSince1970: 1_721_234_567.125)
        let document = PersistableFieldEncoderTestDocument(
            title: "Runtime",
            externalID: externalID,
            occurredAt: occurredAt,
            values: [1, 4, 9]
        )

        let fields = try PersistableFieldEncoder.encode(document)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })

        #expect(byName["externalID"] == .uuid(DatabaseUUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )))
        #expect(byName["note"] == .null)
        #expect(byName["values"] == .array([.uint64(1), .uint64(4), .uint64(9)]))

        let decoded = try PersistableFieldEncoderTestDocument.decodePersistedFields(fields)
        #expect(decoded.id == document.id)
        #expect(decoded.title == document.title)
        #expect(decoded.externalID == externalID)
        #expect(decoded.occurredAt == occurredAt)
        #expect(decoded.note == nil)
        #expect(decoded.values == document.values)
    }

    @Test("Nested Codable values round-trip as canonical objects")
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
}
