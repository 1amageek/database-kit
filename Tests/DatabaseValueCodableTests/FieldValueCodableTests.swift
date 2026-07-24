import Foundation
import Testing
import DatabaseTypes
import DatabaseValue
import DatabaseValueCodable

@Suite("Database Value Codable Adapter")
struct FieldValueCodableTests {
    @Test("Canonical value types round-trip through JSON")
    func roundTrip() throws {
        let literal = try RDFLiteral(
            lexicalForm: "2026-07-18T03:30:00Z",
            datatype: "http://www.w3.org/2001/XMLSchema#dateTime"
        )
        let term = RDFTerm.tripleTerm(
            subject: .iri(
                try RDFIRI("https://example.com/events/1")
            ),
            predicate: try RDFPredicateIRI(
                "https://schema.org/startDate"
            ),
            object: .literal(literal)
        )
        let version = DatabaseSchemaVersion(1, 2, 3)
        let fieldValue = FieldValue.object(
            try FieldObject([
                (key: "term", value: .rdfTerm(term)),
                (key: "unsigned", value: .uint64(UInt64.max)),
            ])
        )

        try expectRoundTrip(literal)
        try expectRoundTrip(term)
        try expectRoundTrip(version)
        try expectRoundTrip(fieldValue)
    }

    private func expectRoundTrip<Value: Codable & Equatable>(
        _ value: Value
    ) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }
}
