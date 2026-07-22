import Core
import DatabaseValue
import Foundation
import Testing

@Suite("Canonical database record encoder")
struct DatabaseRecordEncoderTests {
    @Test("Compiled records round-trip without JSON")
    func compiledRecordRoundTrip() throws {
        let externalID = try #require(
            UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")
        )
        let occurredAt = Date(timeIntervalSince1970: 1_721_234_567.125)
        let record = DatabaseRecordEncoderTestRecord(
            title: "Runtime",
            externalID: externalID,
            occurredAt: occurredAt,
            values: [1, 4, 9]
        )

        let fields = try DatabaseRecordEncoder.encode(record)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })

        #expect(byName["externalID"] == .uuid(DatabaseUUID(
            high: 0x0011_2233_4455_6677,
            low: 0x8899_AABB_CCDD_EEFF
        )))
        #expect(byName["note"] == .null)
        #expect(byName["values"] == .array([.uint64(1), .uint64(4), .uint64(9)]))

        let decoded = try DatabaseRecordEncoderTestRecord.decodeDatabaseRecord(fields)
        #expect(decoded.id == record.id)
        #expect(decoded.title == record.title)
        #expect(decoded.externalID == externalID)
        #expect(decoded.occurredAt == occurredAt)
        #expect(decoded.note == nil)
        #expect(decoded.values == record.values)
    }

    @Test("Nested Codable values round-trip as canonical objects")
    func nestedValueRoundTrip() throws {
        let current = DatabaseRecordNestedValue(label: "current", priority: 2)
        let history = [
            DatabaseRecordNestedValue(label: "created", priority: 0),
            DatabaseRecordNestedValue(label: "updated", priority: 1),
        ]
        let record = DatabaseRecordNestedTestRecord(value: current, history: history)

        let fields = try DatabaseRecordEncoder.encode(record)
        let byName = Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
        guard case .object = byName["value"] else {
            Issue.record("Nested value must use DatabaseValue.object")
            return
        }
        guard case .array(let encodedHistory) = byName["history"] else {
            Issue.record("Nested collection must use DatabaseValue.array")
            return
        }
        #expect(encodedHistory.count == history.count)
        #expect(encodedHistory.allSatisfy {
            if case .object = $0 { return true }
            return false
        })

        let decoded = try DatabaseRecordNestedTestRecord.decodeDatabaseRecord(fields)
        #expect(decoded.value == current)
        #expect(decoded.history == history)
    }
}
