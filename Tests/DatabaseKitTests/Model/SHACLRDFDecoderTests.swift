import DatabaseKit
import DatabaseTypes
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
        #expect(decodedProperty.path == .predicate(try Self.predicate("urn:name")))
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
            property.path == .sequence(
                try SHACLPathList([
                    .inverse(.predicate(try Self.predicate("urn:parent"))),
                    .predicate(try Self.predicate("urn:name"))
                ])
            )
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

    @Test("underspecified compound paths are rejected as path failures")
    func underspecifiedCompoundPathsAreRejected() {
        let propertyShape = Self.iri("urn:InvalidPathShape")
        let pathHead = Self.blankNode("path-head")
        let dataset = RDFDataset(quads: [
            Self.quad(
                propertyShape,
                Self.rdfType,
                Self.iri(Self.shPropertyShape)
            ),
            Self.quad(propertyShape, Self.shPath, pathHead),
            Self.quad(pathHead, Self.rdfFirst, Self.iri("urn:only-member")),
            Self.quad(pathHead, Self.rdfRest, Self.iri(Self.rdfNil))
        ])

        do {
            _ = try SHACLRDFDecoder().decode(
                from: dataset,
                graphIRI: "urn:invalid-path"
            )
            Issue.record("Expected invalidPath")
        } catch SHACLRDFDecodingError.invalidPath(
            .insufficientMembers(actual: 1)
        ) {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("invalid datasets preserve the SHACL failure boundary")
    func invalidDatasetsAreRejected() {
        let shape = Self.iri("urn:InvalidDatasetShape")
        let dataset = RDFDataset(quads: [
            Self.quad(
                shape,
                Self.rdfType,
                Self.nestedTerm(depth: 40)
            )
        ])

        do {
            _ = try SHACLRDFDecoder().decode(
                from: dataset,
                graphIRI: "urn:invalid-dataset"
            )
            Issue.record("Expected invalidDataset")
        } catch SHACLRDFDecodingError.invalidDataset(
            .maximumDepthExceeded
        ) {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static func quad(
        _ subject: RDFTerm,
        _ predicate: String,
        _ object: RDFTerm
    ) -> RDFQuad {
        let typedSubject: RDFSubject
        switch subject {
        case .iri(let iri):
            typedSubject = .iri(iri)
        case .blankNode(let identifier):
            typedSubject = .blankNode(identifier)
        case .literal, .tripleTerm:
            preconditionFailure("A SHACL fixture subject must be an IRI or blank node")
        }
        let typedPredicate: RDFPredicateIRI
        do {
            typedPredicate = try RDFPredicateIRI(predicate)
        } catch {
            preconditionFailure("Invalid SHACL predicate IRI fixture: \(predicate)")
        }
        return RDFQuad(
            subject: typedSubject,
            predicate: typedPredicate,
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

    private static func predicate(
        _ rawValue: String
    ) throws(RDFIRIError) -> RDFPredicateIRI {
        try RDFPredicateIRI(rawValue)
    }

    private static func blankNode(_ rawValue: String) -> RDFTerm {
        do {
            return try .blankNode(identifier: rawValue)
        } catch {
            preconditionFailure("Invalid blank-node fixture: \(rawValue)")
        }
    }

    private static func nestedTerm(depth: Int) -> RDFTerm {
        var term = iri("urn:leaf")
        for _ in 0..<depth {
            term = .tripleTerm(
                subject: subject("urn:nested-subject"),
                predicate: predicateValue("urn:nested-predicate"),
                object: term
            )
        }
        return term
    }

    private static func subject(_ rawValue: String) -> RDFSubject {
        do {
            return .iri(try RDFIRI(rawValue))
        } catch {
            preconditionFailure("Invalid subject fixture: \(rawValue)")
        }
    }

    private static func predicateValue(
        _ rawValue: String
    ) -> RDFPredicateIRI {
        do {
            return try RDFPredicateIRI(rawValue)
        } catch {
            preconditionFailure("Invalid predicate fixture: \(rawValue)")
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
