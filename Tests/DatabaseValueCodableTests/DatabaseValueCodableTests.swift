import Foundation
import Testing
import DatabaseValue
import DatabaseValueCodable

@Suite("Database Value Codable Adapter")
struct DatabaseValueCodableTests {
    @Test("Canonical value types round-trip through JSON")
    func roundTrip() throws {
        let literal = try DatabaseRDFLiteral(
            lexicalForm: "2026-07-18T03:30:00Z",
            datatype: "http://www.w3.org/2001/XMLSchema#dateTime"
        )
        let term = DatabaseRDFTerm.tripleTerm(
            subject: .iri("https://example.com/events/1"),
            predicate: .iri("https://schema.org/startDate"),
            object: .literal(literal)
        )
        let version = DatabaseSchemaVersion(1, 2, 3)

        try expectRoundTrip(literal)
        try expectRoundTrip(term)
        try expectRoundTrip(version)
    }

    private func expectRoundTrip<Value: Codable & Equatable>(
        _ value: Value
    ) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }
}
