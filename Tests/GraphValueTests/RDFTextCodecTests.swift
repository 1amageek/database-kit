import DatabaseTypes
import DatabaseValue
import Graph
import Testing

@Suite("RDF text codecs")
struct RDFTextCodecTests {
    @Test("N-Quads escapes literals in one canonical pass")
    func nQuadsLiteralEscaping() throws {
        let literal = "slash \\ quote \" line\nreturn\rtab\t"
        let dataset = RDFDataset(quads: [
            RDFQuad(
                subject: .iri(try RDFIRI("urn:subject")),
                predicate: try RDFPredicateIRI("urn:predicate"),
                object: .literal(RDFLiteral(
                    lexicalForm: literal,
                    datatype: .xsdString
                ))
            )
        ])

        let encoded = try NQuadsEncoder().encode(dataset)

        #expect(
            encoded
                == "<urn:subject> <urn:predicate> \"slash \\\\ quote \\\" line\\nreturn\\rtab\\t\" .\n"
        )
        #expect(try NQuadsDecoder().decode(from: encoded) == dataset)
    }

    @Test("Turtle uses the shared canonical literal escaping")
    func turtleLiteralEscaping() {
        let ontology = OWLOntology(
            iri: "urn:ontology",
            classes: [
                OWLClass(
                    iri: "urn:Class",
                    label: "slash \\ quote \" line\nreturn\rtab\t"
                )
            ]
        )

        let encoded = TurtleEncoder().encode(ontology)

        #expect(
            UTF8Text.contains(
                "rdfs:label \"slash \\\\ quote \\\" line\\nreturn\\rtab\\t\"",
                in: encoded
            )
        )
    }

    @Test("IRI scheme detection is byte exact")
    func iriSchemeDetection() throws {
        let dataset = try TriGDecoder().decode(
            from: "@base <https://example.com/> . <child> <urn:p> <value> ."
        )

        let expectedSubject = RDFSubject.iri(
            try RDFIRI("https://example.com/child")
        )
        let expectedObject = try RDFTerm.iri(
            validating: "https://example.com/value"
        )
        #expect(dataset.quads.first?.subject == expectedSubject)
        #expect(dataset.quads.first?.object == expectedObject)
    }
}
