import DatabaseTypes
import DatabaseKit
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

    @Test("N-Quads formats one validated quad without a trailing newline")
    func nQuadsSingleQuadFormatting() throws {
        let quad = RDFQuad(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: try RDFPredicateIRI("urn:predicate"),
            object: .literal(.string("value")),
            graph: RDFGraphName(
                RDFSubject.iri(try RDFIRI("urn:graph"))
            )
        )

        let formatted = try NQuadsEncoder().format(quad)

        #expect(
            formatted
                == "<urn:subject> <urn:predicate> \"value\" <urn:graph> ."
        )
        #expect(!formatted.hasSuffix("\n"))
    }

    @Test("N-Quads single-quad formatting enforces validation limits")
    func nQuadsSingleQuadFormattingRejectsExcessiveDepth() throws {
        var object = RDFTerm.iri(try RDFIRI("urn:object"))
        for depth in 0..<40 {
            object = .tripleTerm(
                subject: .iri(try RDFIRI("urn:nested:\(depth)")),
                predicate: try RDFPredicateIRI("urn:predicate"),
                object: object
            )
        }
        let quad = RDFQuad(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: try RDFPredicateIRI("urn:predicate"),
            object: object
        )

        #expect(throws: RDFTermValidationError.self) {
            _ = try NQuadsEncoder().format(quad)
        }
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
            encoded.contains(
                "rdfs:label \"slash \\\\ quote \\\" line\\nreturn\\rtab\\t\""
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
