import DatabaseKit
import DatabaseTypes

extension RDFQuad: WireValue {
    func encode(
        into writer: inout DatabaseWireWriter
    ) throws(DatabaseWireError) {
        try writer.writeCanonicalRDFTerm(subject.term, role: .subject)
        try writer.writeCanonicalRDFTerm(predicate.term, role: .predicate)
        try writer.writeCanonicalRDFTerm(object, role: .object)
        writer.writeBool(graph != nil)
        if let graph {
            try writer.writeCanonicalRDFTerm(
                graph.term,
                role: .graphName
            )
        }
    }

    init(
        from reader: inout DatabaseWireReader
    ) throws(DatabaseWireError) {
        let subjectTerm = try reader.readCanonicalRDFTerm(role: .subject)
        let subject: RDFSubject
        switch subjectTerm {
        case .iri(let iri):
            subject = .iri(iri)
        case .blankNode(let identifier):
            subject = .blankNode(identifier)
        case .literal, .tripleTerm:
            throw .invalidRDFTripleSubject
        }

        let predicateTerm = try reader.readCanonicalRDFTerm(role: .predicate)
        guard case .iri(let predicateIRI) = predicateTerm else {
            throw .invalidRDFTriplePredicate
        }
        let predicate = RDFPredicateIRI(predicateIRI)
        let object = try reader.readCanonicalRDFTerm(role: .object)
        guard try reader.readBool() else {
            self.init(
                subject: subject,
                predicate: predicate,
                object: object
            )
            return
        }

        let graphTerm = try reader.readCanonicalRDFTerm(role: .graphName)
        let graph: RDFGraphName
        switch graphTerm {
        case .iri(let iri):
            graph = RDFGraphName(RDFSubject.iri(iri))
        case .blankNode(let identifier):
            graph = RDFGraphName(RDFSubject.blankNode(identifier))
        case .literal, .tripleTerm:
            throw .invalidRDFGraphName
        }
        self.init(
            subject: subject,
            predicate: predicate,
            object: object,
            graph: graph
        )
    }
}
