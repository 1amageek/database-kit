/// The ontology role compiled into one persisted entity declaration.
///
/// This is schema data, not a runtime type capability. It can therefore cross
/// process boundaries and remain available in Embedded builds.
public enum OntologyBinding: Sendable, Hashable {
    case owlClass(
        iri: String,
        dataPropertyIRIs: [String]
    )
    case owlObjectProperty(
        iri: String,
        fromField: String,
        toField: String,
        dataPropertyIRIs: [String]
    )

    public var dataPropertyIRIs: [String] {
        switch self {
        case .owlClass(_, let iris):
            return iris
        case .owlObjectProperty(_, _, _, let iris):
            return iris
        }
    }
}
