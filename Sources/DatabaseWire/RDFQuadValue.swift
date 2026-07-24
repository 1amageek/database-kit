import DatabaseTypes

/// An RDF quad carried by database operations.
///
/// The positional types make invalid subjects, predicates, and graph names
/// unrepresentable after decoding or construction.
public struct RDFQuadValue: DatabaseWireValue, Hashable {
    public let subject: RDFSubject
    public let predicate: RDFPredicateIRI
    public let object: RDFTerm
    public let graph: RDFSubject?

    public init(
        subject: RDFSubject,
        predicate: RDFPredicateIRI,
        object: RDFTerm,
        graph: RDFSubject? = nil
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }

    public func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCanonicalRDFTerm(subject.term, role: .subject)
        try writer.writeCanonicalRDFTerm(predicate.term, role: .predicate)
        try writer.writeCanonicalRDFTerm(object, role: .object)
        writer.writeBool(graph != nil)
        if let graph {
            try writer.writeCanonicalRDFTerm(graph.term, role: .graphName)
        }
    }

    public init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let subjectTerm = try reader.readCanonicalRDFTerm(role: .subject)
        switch subjectTerm {
        case .iri(let iri):
            self.subject = .iri(iri)
        case .blankNode(let identifier):
            self.subject = .blankNode(identifier)
        case .literal, .tripleTerm:
            throw .invalidRDFTripleSubject
        }

        let predicateTerm = try reader.readCanonicalRDFTerm(role: .predicate)
        guard case .iri(let predicateIRI) = predicateTerm else {
            throw .invalidRDFTriplePredicate
        }
        self.predicate = RDFPredicateIRI(predicateIRI)
        self.object = try reader.readCanonicalRDFTerm(role: .object)
        guard try reader.readBool() else {
            self.graph = nil
            return
        }

        let graphTerm = try reader.readCanonicalRDFTerm(role: .graphName)
        switch graphTerm {
        case .iri(let iri):
            self.graph = .iri(iri)
        case .blankNode(let identifier):
            self.graph = .blankNode(identifier)
        case .literal, .tripleTerm:
            throw .invalidRDFGraphName
        }
    }
}
