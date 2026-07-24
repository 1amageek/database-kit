import DatabaseTypes
import DatabaseValue
import Graph
import Testing

@Suite("RDF graph name")
struct RDFGraphNameTests {
    @Test("Accepts absolute IRI and blank node graph names")
    func acceptsNamedGraphTerms() throws {
        let iri = try RDFGraphName(iri: "https://example.com/graphs/events")
        let blankNode = try RDFGraphName(blankNodeIdentifier: "graph-1")
        let expectedIRI = try RDFTerm.iri(
            validating: "https://example.com/graphs/events"
        )
        let expectedBlankNode = try RDFTerm.blankNode(
            identifier: "graph-1"
        )

        #expect(iri.term == expectedIRI)
        #expect(blankNode.term == expectedBlankNode)
    }

    @Test(
        "Rejects terms that cannot name an RDF graph",
        arguments: [
            RDFTerm.literal(
                RDFLiteral(
                    lexicalForm: "events",
                    datatype: XSDDatatype.string.typedLiteralDatatype
                )
            ),
        ]
    )
    func rejectsInvalidGraphNames(_ term: RDFTerm) {
        #expect(throws: RDFDatasetValidationError.self) {
            _ = try RDFGraphName(term)
        }
    }
}
