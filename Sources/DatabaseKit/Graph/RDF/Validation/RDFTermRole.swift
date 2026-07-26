/// A position whose RDF grammar constrains the allowed term forms.
public enum RDFTermRole: Sendable, Equatable {
    case term
    case subject
    case predicate
    case object
    case graphName
}
