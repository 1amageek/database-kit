import DatabaseTypes
import DatabaseKit
import Testing

@Suite("OWL Literal Value Tests")
struct OWLLiteralValueTests {
    @Test func dateLiteralUsesCanonicalFoundationIndependentValue() throws {
        let date = try CivilDate(year: 2026, month: 7, day: 20)
        let literal = try RDFLiteral.date(date)

        #expect(literal.lexicalForm == "2026-07-20")
        #expect(literal.datatypeIRI == XSDDatatype.date.iri)
        #expect(literal.databaseDateValue == date)
        #expect(literal.timestampValue == nil)
    }

    @Test func timestampLiteralPreservesNanosecondsExactly() throws {
        let timestamp = try Timestamp(
            secondsSinceUnixEpoch: 1_752_995_696,
            nanoseconds: 123_456_789
        )
        let literal = try RDFLiteral.dateTime(timestamp)

        #expect(literal.lexicalForm == "2025-07-20T07:14:56.123456789Z")
        #expect(literal.datatypeIRI == XSDDatatype.dateTime.iri)
        #expect(literal.timestampValue == timestamp)
        #expect(literal.databaseDateValue == nil)
    }

    @Test func booleanLexicalExtractionIsCaseSensitive() {
        #expect(RDFLiteral.boolean(true).boolValue == true)
        #expect(RDFLiteral.boolean(false).boolValue == false)
        #expect(
            RDFLiteral(
                lexicalForm: "TRUE",
                datatype: XSDDatatype.boolean.typedLiteralDatatype
            ).boolValue == nil
        )
    }

    @Test func scalarTimestampProjectionUsesTheSameCanonicalCodec() throws {
        let timestamp = try Timestamp(
            secondsSinceUnixEpoch: 0,
            nanoseconds: 1
        )
        let term = try timestamp.owlDataPropertyTerm()

        guard case .literal(let literal) = term else {
            Issue.record("Timestamp must project to an RDF literal")
            return
        }
        #expect(literal.lexicalForm == "1970-01-01T00:00:00.000000001Z")
        #expect(literal.datatypeIRI == XSDDatatype.dateTime.iri)
    }
}
