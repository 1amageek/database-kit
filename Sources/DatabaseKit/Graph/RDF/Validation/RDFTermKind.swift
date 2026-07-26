/// The semantic form represented by an RDF term.
public enum RDFTermKind: Sendable, Equatable {
    case blankNode
    case iri
    case literal
    case tripleTerm
}
