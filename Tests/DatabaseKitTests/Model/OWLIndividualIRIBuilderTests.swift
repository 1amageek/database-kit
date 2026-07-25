import DatabaseKit
import DatabaseTypes
import Testing

@Suite("OWL individual IRI builder")
struct OWLIndividualIRIBuilderTests {
    @Test("Subject construction preserves an IRI result")
    func subjectConstructionPreservesIRIResult() throws {
        let subject = try OWLIndividualIRIBuilder.subject(
            baseIRI: "https://example.com/individuals",
            persistableType: "Calendar Event",
            identifier: "event/1"
        )

        #expect(
            subject == .iri(
                try RDFIRI(
                    "https://example.com/individuals/"
                        + "Calendar%20Event/event%2F1"
                )
            )
        )
    }

    @Test("Relative base IRI returns the typed projection failure")
    func relativeBaseIRIReturnsProjectionFailure() {
        #expect(
            throws: OWLProjectionError.invalidIndividualIRIBase(
                "relative-base"
            )
        ) {
            try OWLIndividualIRIBuilder.term(
                baseIRI: "relative-base",
                persistableType: "Event",
                identifier: "event-1"
            )
        }
    }

    @Test("RDF type vocabulary resolves to the canonical predicate")
    func rdfTypeVocabularyResolvesCanonicalPredicate() throws {
        let predicate = try OWLRDFVocabulary.rdfType

        #expect(
            predicate.rawValue
                == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        )
    }
}
