import DatabaseValue
import Graph
import Testing

@Suite("RDF graph name")
struct RDFGraphNameTests {
    @Test("Accepts absolute IRI and blank node graph names")
    func acceptsNamedGraphTerms() throws {
        let iri = try RDFGraphName(iri: "https://example.com/graphs/events")
        let blankNode = try RDFGraphName(blankNodeIdentifier: "graph-1")

        #expect(iri.term == .iri("https://example.com/graphs/events"))
        #expect(blankNode.term == .blankNode("graph-1"))
    }

    @Test(
        "Rejects terms that cannot name an RDF graph",
        arguments: [
            DatabaseRDFTerm.iri("relative"),
            .blankNode(""),
            .literal(
                DatabaseRDFLiteral(
                    lexicalForm: "events",
                    datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
                )
            ),
        ]
    )
    func rejectsInvalidGraphNames(_ term: DatabaseRDFTerm) {
        #expect(throws: RDFDatasetValidationError.self) {
            _ = try RDFGraphName(term)
        }
    }
}
