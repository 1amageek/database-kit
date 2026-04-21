import Testing
@testable import Graph

@Suite("RDF Dataset Codecs")
struct RDFDatasetCodecTests {

    @Test("N-Quads decodes default graph and named graph quads")
    func nQuadsDecode() throws {
        let input = """
        <http://example.org/alice> <http://example.org/knows> <http://example.org/bob> .
        <http://example.org/alice> <http://example.org/name> "Alice"@en <http://example.org/doc/1> .
        <http://example.org/alice> <http://example.org/age> "30"^^<http://www.w3.org/2001/XMLSchema#integer> <http://example.org/doc/1> .
        """

        let dataset = try NQuadsDecoder().decode(from: input)

        #expect(dataset.quads.count == 3)
        #expect(dataset.quads[0].graph == nil)
        #expect(dataset.quads[1].graph == .iri("http://example.org/doc/1"))
        #expect(dataset.quads[2].object == .literal(.typed("30", datatype: "http://www.w3.org/2001/XMLSchema#integer")))
    }

    @Test("N-Quads rejects invalid predicate")
    func nQuadsRejectsInvalidPredicate() throws {
        let input = """
        <http://example.org/alice> "not-a-predicate" <http://example.org/bob> .
        """

        #expect(throws: RDFSyntaxError.self) {
            _ = try NQuadsDecoder().decode(from: input)
        }
    }

    @Test("N-Quads decodes blank nodes, escaped literals, and comments")
    func nQuadsDecodeBlankNodesEscapesAndComments() throws {
        let input = """
        # leading comment
        _:alice <http://example.org/knows> _:bob <http://example.org/doc#1> . # trailing comment
        <http://example.org/alice#id> <http://example.org/label> "Alice #1\\nAgent"@en .
        """

        let dataset = try NQuadsDecoder().decode(from: input)

        #expect(dataset.quads.count == 2)
        #expect(dataset.quads[0].subject == .blankNode("alice"))
        #expect(dataset.quads[0].object == .blankNode("bob"))
        #expect(dataset.quads[0].graph == .iri("http://example.org/doc#1"))
        #expect(dataset.quads[1].subject == .iri("http://example.org/alice#id"))
        #expect(dataset.quads[1].object == .literal(.langString("Alice #1\nAgent", language: "en")))
    }

    @Test("N-Quads rejects literal graph names")
    func nQuadsRejectsLiteralGraphName() throws {
        let input = """
        <http://example.org/alice> <http://example.org/knows> <http://example.org/bob> "not-a-graph" .
        """

        #expect(throws: RDFSyntaxError.self) {
            _ = try NQuadsDecoder().decode(from: input)
        }
    }

    @Test("N-Quads encoder is deterministic and round-trips")
    func nQuadsRoundTrip() throws {
        let dataset = RDFDataset(quads: [
            RDFQuad(
                subject: .iri("http://example.org/b"),
                predicate: .iri("http://example.org/p"),
                object: .iri("http://example.org/o"),
                graph: .iri("http://example.org/g")
            ),
            RDFQuad(
                subject: .iri("http://example.org/a"),
                predicate: .iri("http://example.org/p"),
                object: .literal(.langString("hello", language: "en"))
            ),
        ])

        let encoded = try NQuadsEncoder().encode(dataset)
        let decoded = try NQuadsDecoder().decode(from: encoded)

        #expect(encoded.split(separator: "\n").first == "<http://example.org/a> <http://example.org/p> \"hello\"@en .")
        #expect(Set(decoded.quads) == Set(dataset.quads))
    }

    @Test("RDFDataset validation rejects invalid subject and graph terms")
    func rdfDatasetValidationRejectsInvalidTerms() throws {
        let invalidSubject = RDFDataset(quads: [
            RDFQuad(
                subject: .literal(.string("Alice")),
                predicate: .iri("http://example.org/knows"),
                object: .iri("http://example.org/bob")
            )
        ])
        #expect(throws: RDFDatasetValidationError.self) {
            try invalidSubject.validate()
        }

        let invalidGraph = RDFDataset(quads: [
            RDFQuad(
                subject: .iri("http://example.org/alice"),
                predicate: .iri("http://example.org/knows"),
                object: .iri("http://example.org/bob"),
                graph: .literal(.string("doc"))
            )
        ])
        #expect(throws: RDFDatasetValidationError.self) {
            _ = try NQuadsEncoder().encode(invalidGraph)
        }
    }

    @Test("TriG decodes prefixes, default graph, named graph blocks, and merged graph blocks")
    func triGDecode() throws {
        let input = """
        @prefix ex: <http://example.org/> .
        @base <http://base.example/> .

        ex:alice ex:knows ex:bob .

        ex:doc1 {
            ex:alice ex:name "Alice"@en ;
                ex:age 30 .
        }

        GRAPH ex:doc1 {
            ex:receipt ex:settles ex:invoice .
        }
        """

        let dataset = try TriGDecoder().decode(from: input)

        #expect(dataset.baseIRI == "http://base.example/")
        #expect(dataset.prefixes["ex"] == "http://example.org/")
        #expect(dataset.quads.count == 4)
        #expect(dataset.quads.filter { $0.graph == nil }.count == 1)
        #expect(dataset.quads.filter { $0.graph == .iri("http://example.org/doc1") }.count == 3)
    }

    @Test("TriG decodes SPARQL-style PREFIX and BASE")
    func triGDecodeSPARQLPrefixAndBase() throws {
        let input = """
        PREFIX ex: <http://example.org/>
        BASE <http://base.example/>

        <relative> ex:predicate ex:object .
        """

        let dataset = try TriGDecoder().decode(from: input)

        #expect(dataset.baseIRI == "http://base.example/")
        #expect(dataset.prefixes["ex"] == "http://example.org/")
        #expect(dataset.quads == [
            RDFQuad(
                subject: .iri("http://base.example/relative"),
                predicate: .iri("http://example.org/predicate"),
                object: .iri("http://example.org/object")
            )
        ])
    }

    @Test("TriG keeps blank node property lists and collections in their named graph")
    func triGBlankNodesAndCollectionsStayInNamedGraph() throws {
        let input = """
        @prefix ex: <http://example.org/> .

        ex:doc {
            [ ex:name "Alice" ] ex:memberOf ex:crew .
            ex:list ex:items (ex:a ex:b) .
        }
        """

        let dataset = try TriGDecoder().decode(from: input)
        let graph = RDFTerm.iri("http://example.org/doc")

        #expect(dataset.quads.count == 7)
        #expect(dataset.quads.allSatisfy { $0.graph == graph })
        #expect(dataset.quads.contains {
            $0.predicate == .iri("http://example.org/name") &&
            $0.object == .literal(.string("Alice")) &&
            $0.graph == graph
        })
        #expect(dataset.quads.contains {
            $0.subject == .iri("http://example.org/list") &&
            $0.predicate == .iri("http://example.org/items") &&
            $0.graph == graph
        })
    }

    @Test("TriG rejects undefined prefixes and literal graph names")
    func triGRejectsInvalidTerms() throws {
        #expect(throws: RDFSyntaxError.self) {
            _ = try TriGDecoder().decode(from: "ex:alice ex:knows ex:bob .")
        }

        #expect(throws: RDFSyntaxError.self) {
            _ = try TriGDecoder().decode(from: """
            GRAPH "literal graph" {
                <http://example.org/alice> <http://example.org/knows> <http://example.org/bob> .
            }
            """)
        }
    }

    @Test("TriG encoder groups by graph and round-trips")
    func triGRoundTrip() throws {
        let dataset = RDFDataset(
            prefixes: ["ex": "http://example.org/"],
            quads: [
                RDFQuad(
                    subject: .iri("http://example.org/alice"),
                    predicate: .iri("http://example.org/knows"),
                    object: .iri("http://example.org/bob")
                ),
                RDFQuad(
                    subject: .iri("http://example.org/receipt"),
                    predicate: .iri("http://example.org/settles"),
                    object: .iri("http://example.org/invoice"),
                    graph: .iri("http://example.org/doc")
                ),
            ]
        )

        let encoded = try TriGEncoder().encode(dataset)
        let decoded = try TriGDecoder().decode(from: encoded)

        #expect(encoded.contains("ex:doc {"))
        #expect(Set(decoded.quads) == Set(dataset.quads))
    }
}
