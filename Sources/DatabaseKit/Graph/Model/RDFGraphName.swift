import DatabaseTypes

/// A validated RDF named-graph identifier.
///
/// The RDF default graph has no name and is therefore represented elsewhere
/// by `nil`. This value can only contain an absolute IRI or a non-empty blank
/// node identifier.
public struct RDFGraphName: Sendable, Hashable, Comparable {
    public let subject: RDFSubject

    public var term: RDFTerm {
        subject.term
    }

    public init(_ subject: RDFSubject) {
        self.subject = subject
    }

    public init(_ term: RDFTerm) throws {
        switch term {
        case .iri(let iri):
            self.subject = .iri(iri)
        case .blankNode(let identifier):
            self.subject = .blankNode(identifier)
        case .literal, .tripleTerm:
            throw RDFDatasetValidationError.invalidGraphName(term)
        }
    }

    public init(iri: String) throws {
        self.init(RDFSubject.iri(try RDFIRI(iri)))
    }

    public init(blankNodeIdentifier: String) throws {
        self.init(
            RDFSubject.blankNode(
                try RDFBlankNodeIdentifier(blankNodeIdentifier)
            )
        )
    }

    public static func < (lhs: RDFGraphName, rhs: RDFGraphName) -> Bool {
        lhs.subject < rhs.subject
    }
}
