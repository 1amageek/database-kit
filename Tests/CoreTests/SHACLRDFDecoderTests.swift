import DatabaseTypes
import DatabaseValue
import Graph
import Testing

@Suite("SHACL RDF decoder")
struct SHACLRDFDecoderTests {
    @Test("node and property shapes decode from canonical RDF")
    func nodeAndPropertyShapesDecode() throws {
        let nodeShape = Self.iri("urn:PersonShape")
        let propertyShape = Self.blankNode("name-property")
        let dataset = RDFDataset(quads: [
            Self.quad(nodeShape, Self.rdfType, Self.iri(Self.shNodeShape)),
            Self.quad(nodeShape, Self.shTargetClass, Self.iri("urn:Person")),
            Self.quad(nodeShape, Self.shProperty, propertyShape),
            Self.quad(propertyShape, Self.rdfType, Self.iri(Self.shPropertyShape)),
            Self.quad(propertyShape, Self.shPath, Self.iri("urn:name")),
            Self.quad(propertyShape, Self.shMinCount, Self.integer(1)),
            Self.quad(propertyShape, Self.shDatatype, Self.iri(Self.xsdString)),
            Self.quad(propertyShape, Self.shMessage, .string("A name is required"))
        ])

        let graph = try SHACLRDFDecoder().decode(
            from: dataset,
            graphIRI: "urn:calendar-shapes"
        )

        #expect(graph.iri == "urn:calendar-shapes")
        #expect(graph.shapes.count == 2)
        guard let shape = graph.findShape(identifier: nodeShape),
              case .node(let decodedNode) = shape,
              let decodedProperty = decodedNode.propertyShapes.first else {
            Issue.record("Expected a decoded node shape and property shape")
            return
        }
        #expect(decodedNode.targets == [.class_("urn:Person")])
        #expect(decodedNode.identifier == nodeShape)
        #expect(decodedProperty.identifier == propertyShape)
        #expect(decodedProperty.path == .predicate("urn:name"))
        #expect(decodedProperty.constraints.contains(.minCount(1)))
        #expect(decodedProperty.constraints.contains(.datatype(Self.xsdString)))
        #expect(decodedProperty.messages == ["A name is required"])
    }

    @Test("compound property paths decode through RDF lists")
    func compoundPathsDecode() throws {
        let propertyShape = Self.iri("urn:AncestorNameShape")
        let pathHead = Self.blankNode("path-head")
        let pathTail = Self.blankNode("path-tail")
        let inverse = Self.blankNode("inverse")
        let dataset = RDFDataset(quads: [
            Self.quad(propertyShape, Self.rdfType, Self.iri(Self.shPropertyShape)),
            Self.quad(propertyShape, Self.shPath, pathHead),
            Self.quad(pathHead, Self.rdfFirst, inverse),
            Self.quad(pathHead, Self.rdfRest, pathTail),
            Self.quad(pathTail, Self.rdfFirst, Self.iri("urn:name")),
            Self.quad(pathTail, Self.rdfRest, Self.iri(Self.rdfNil)),
            Self.quad(inverse, Self.shInversePath, Self.iri("urn:parent"))
        ])

        let graph = try SHACLRDFDecoder().decode(
            from: dataset,
            graphIRI: "urn:paths"
        )

        guard let shape = graph.findShape(identifier: propertyShape),
              case .property(let property) = shape else {
            Issue.record("Expected a property shape")
            return
        }
        #expect(
            property.path == .sequence([
                .inverse(.predicate("urn:parent")),
                .predicate("urn:name")
            ])
        )
    }

    @Test("unknown SHACL predicates are rejected")
    func unknownPredicatesAreRejected() {
        let shape = Self.iri("urn:UnsupportedShape")
        let dataset = RDFDataset(quads: [
            Self.quad(shape, Self.rdfType, Self.iri(Self.shNodeShape)),
            Self.quad(
                shape,
                "http://www.w3.org/ns/shacl#sparql",
                Self.blankNode("constraint")
            )
        ])

        #expect(throws: SHACLRDFDecodingError.self) {
            try SHACLRDFDecoder().decode(
                from: dataset,
                graphIRI: "urn:unsupported"
            )
        }
    }

    private static func quad(
        _ subject: RDFTerm,
        _ predicate: String,
        _ object: RDFTerm
    ) -> RDFQuad {
        RDFQuad(
            subject: subject,
            predicate: Self.iri(predicate),
            object: object
        )
    }

    private static func integer(_ value: Int) -> RDFTerm {
        .literal(.integer(value))
    }

    private static func iri(_ rawValue: String) -> RDFTerm {
        do {
            return try .iri(validating: rawValue)
        } catch {
            preconditionFailure("Invalid RDF IRI fixture: \(rawValue)")
        }
    }

    private static func blankNode(_ rawValue: String) -> RDFTerm {
        do {
            return try .blankNode(identifier: rawValue)
        } catch {
            preconditionFailure("Invalid blank-node fixture: \(rawValue)")
        }
    }

    private static let rdfNamespace =
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    private static let shNamespace = "http://www.w3.org/ns/shacl#"
    private static let rdfType = rdfNamespace + "type"
    private static let rdfFirst = rdfNamespace + "first"
    private static let rdfRest = rdfNamespace + "rest"
    private static let rdfNil = rdfNamespace + "nil"
    private static let shNodeShape = shNamespace + "NodeShape"
    private static let shPropertyShape = shNamespace + "PropertyShape"
    private static let shTargetClass = shNamespace + "targetClass"
    private static let shProperty = shNamespace + "property"
    private static let shPath = shNamespace + "path"
    private static let shInversePath = shNamespace + "inversePath"
    private static let shMinCount = shNamespace + "minCount"
    private static let shDatatype = shNamespace + "datatype"
    private static let shMessage = shNamespace + "message"
    private static let xsdString =
        "http://www.w3.org/2001/XMLSchema#string"
}
