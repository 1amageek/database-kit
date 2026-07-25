import DatabaseTypes
import Testing
@testable import DatabaseKit

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
        #expect(dataset.quads[1].graph == fixtureGraphIRI("http://example.org/doc/1"))
        let expected = RDFTerm.literal(
            .typed(
                "30",
                datatype: XSDDatatype.integer.typedLiteralDatatype
            )
        )
        #expect(dataset.quads[2].object == expected)
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
        #expect(dataset.quads[0].subject == fixtureSubjectBlankNode("alice"))
        #expect(dataset.quads[0].object == fixtureBlankNode("bob"))
        #expect(dataset.quads[0].graph == fixtureGraphIRI("http://example.org/doc#1"))
        #expect(dataset.quads[1].subject == fixtureSubjectIRI("http://example.org/alice#id"))
        let expected = RDFTerm.literal(
            .langString(
                "Alice #1\nAgent",
                language: try RDFLanguageTag("en")
            )
        )
        #expect(dataset.quads[1].object == expected)
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
                subject: fixtureSubjectIRI("http://example.org/b"),
                predicate: fixturePredicateIRI("http://example.org/p"),
                object: fixtureIRI("http://example.org/o"),
                graph: fixtureGraphIRI("http://example.org/g")
            ),
            RDFQuad(
                subject: fixtureSubjectIRI("http://example.org/a"),
                predicate: fixturePredicateIRI("http://example.org/p"),
                object: .literal(
                    .langString(
                        "hello",
                        language: try RDFLanguageTag("en")
                    )
                )
            ),
        ])

        let encoded = try NQuadsEncoder().encode(dataset)
        let decoded = try NQuadsDecoder().decode(from: encoded)

        #expect(encoded.split(separator: "\n").first == "<http://example.org/a> <http://example.org/p> \"hello\"@en .")
        #expect(Set(decoded.quads) == Set(dataset.quads))
    }

    @Test("N-Quads rejects literal subjects")
    func nQuadsRejectsLiteralSubject() {
        #expect(throws: RDFSyntaxError.self) {
            _ = try NQuadsDecoder().decode(
                from: "\"Alice\" <http://example.org/knows> <http://example.org/bob> ."
            )
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
        #expect(dataset.quads.filter { $0.graph == fixtureGraphIRI("http://example.org/doc1") }.count == 3)
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
                subject: fixtureSubjectIRI("http://base.example/relative"),
                predicate: fixturePredicateIRI("http://example.org/predicate"),
                object: fixtureIRI("http://example.org/object")
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
        let graph = fixtureGraphIRI("http://example.org/doc")

        #expect(dataset.quads.count == 7)
        #expect(dataset.quads.allSatisfy { $0.graph == graph })
        #expect(dataset.quads.contains {
            $0.predicate == fixturePredicateIRI("http://example.org/name") &&
            $0.object == .literal(.string("Alice")) &&
            $0.graph == graph
        })
        #expect(dataset.quads.contains {
            $0.subject == fixtureSubjectIRI("http://example.org/list") &&
            $0.predicate == fixturePredicateIRI("http://example.org/items") &&
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
                    subject: fixtureSubjectIRI("http://example.org/alice"),
                    predicate: fixturePredicateIRI("http://example.org/knows"),
                    object: fixtureIRI("http://example.org/bob")
                ),
                RDFQuad(
                    subject: fixtureSubjectIRI("http://example.org/receipt"),
                    predicate: fixturePredicateIRI("http://example.org/settles"),
                    object: fixtureIRI("http://example.org/invoice"),
                    graph: fixtureGraphIRI("http://example.org/doc")
                ),
            ]
        )

        let encoded = try TriGEncoder().encode(dataset)
        let decoded = try TriGDecoder().decode(from: encoded)

        #expect(encoded.contains("ex:doc {"))
        #expect(Set(decoded.quads) == Set(dataset.quads))
    }

    @Test("RDF text encoders reject datasets beyond the canonical depth")
    func encodersRejectExcessiveTermDepth() {
        let dataset = RDFDataset(quads: [
            RDFQuad(
                subject: fixtureSubjectIRI("urn:subject"),
                predicate: fixturePredicateIRI("urn:predicate"),
                object: fixtureNestedTerm(depth: 40)
            )
        ])

        #expect(throws: RDFTermCodecError.self) {
            _ = try NQuadsEncoder().encode(dataset)
        }
        #expect(throws: RDFTermCodecError.self) {
            _ = try TriGEncoder().encode(dataset)
        }
    }
}

private func fixtureIRI(_ rawValue: String) -> RDFTerm {
    do {
        return try .iri(validating: rawValue)
    } catch {
        preconditionFailure("Invalid RDF IRI fixture: \(rawValue)")
    }
}

private func fixtureSubjectIRI(_ rawValue: String) -> RDFSubject {
    do {
        return .iri(try RDFIRI(rawValue))
    } catch {
        preconditionFailure("Invalid RDF subject IRI fixture: \(rawValue)")
    }
}

private func fixturePredicateIRI(_ rawValue: String) -> RDFPredicateIRI {
    do {
        return try RDFPredicateIRI(rawValue)
    } catch {
        preconditionFailure("Invalid RDF predicate IRI fixture: \(rawValue)")
    }
}

private func fixtureGraphIRI(_ rawValue: String) -> RDFGraphName {
    do {
        return RDFGraphName(RDFSubject.iri(try RDFIRI(rawValue)))
    } catch {
        preconditionFailure("Invalid RDF graph IRI fixture: \(rawValue)")
    }
}

private func fixtureBlankNode(_ rawValue: String) -> RDFTerm {
    do {
        return try .blankNode(identifier: rawValue)
    } catch {
        preconditionFailure("Invalid blank-node fixture: \(rawValue)")
    }
}

private func fixtureNestedTerm(depth: Int) -> RDFTerm {
    var term = fixtureIRI("urn:leaf")
    for _ in 0..<depth {
        term = .tripleTerm(
            subject: fixtureSubjectIRI("urn:nested-subject"),
            predicate: fixturePredicateIRI("urn:nested-predicate"),
            object: term
        )
    }
    return term
}

private func fixtureSubjectBlankNode(_ rawValue: String) -> RDFSubject {
    do {
        return .blankNode(try RDFBlankNodeIdentifier(rawValue))
    } catch {
        preconditionFailure("Invalid RDF subject blank-node fixture: \(rawValue)")
    }
}
