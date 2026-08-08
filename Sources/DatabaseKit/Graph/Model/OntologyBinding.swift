/// The ontology role compiled into one persisted entity declaration.
///
/// This is schema data, not a runtime type capability. It can therefore cross
/// process boundaries and remain available in Embedded builds.
public enum OntologyBinding: Sendable, Hashable {
    case owlClass(
        iri: String,
        properties: [OWLDataPropertyDescriptor]
    )
    case owlObjectProperty(
        iri: String,
        fromField: String,
        toField: String,
        properties: [OWLDataPropertyDescriptor]
    )

    public var dataPropertyIRIs: [String] {
        propertyDescriptors.map { $0.iri }
    }

    public var propertyDescriptors: [OWLDataPropertyDescriptor] {
        switch self {
        case .owlClass(_, let properties):
            return properties
        case .owlObjectProperty(_, _, _, let properties):
            return properties
        }
    }
}
