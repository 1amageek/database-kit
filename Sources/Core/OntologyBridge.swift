/// Internal bridge protocol for runtime access to OWL class IRI.
///
/// Allows `Schema.Entity` (in Core) to extract ontology metadata
/// without a circular dependency on the Graph module.
/// Graph's `OWLClassEntity` conforms to this protocol.
public protocol _OWLClassIRIProvider {
    static var ontologyClassIRI: String { get }
}

/// Backward compatibility alias
@available(*, deprecated, renamed: "_OWLClassIRIProvider")
public typealias _OntologyClassIRIProvider = _OWLClassIRIProvider

/// Internal bridge protocol for runtime access to OWL ObjectProperty metadata.
///
/// Allows `Schema.Entity` (in Core) to extract ObjectProperty info
/// without a circular dependency on the Graph module.
/// Graph's `OWLObjectPropertyEntity` conforms to this protocol.
public protocol _OWLObjectPropertyIRIProvider {
    static var objectPropertyIRI: String { get }
    static var fromFieldName: String { get }
    static var toFieldName: String { get }
}

/// Backward compatibility alias
@available(*, deprecated, renamed: "_OWLObjectPropertyIRIProvider")
public typealias _ObjectPropertyIRIProvider = _OWLObjectPropertyIRIProvider

/// Internal bridge protocol for runtime access to OWL DataProperty IRIs.
///
/// Allows `Schema.Entity` (in Core) to extract data property IRIs
/// without a circular dependency on the Graph module.
/// Both `OWLClassEntity` and `OWLObjectPropertyEntity` conform to this
/// via `ontologyPropertyDescriptors`.
public protocol _DataPropertyIRIsProvider {
    static var dataPropertyIRIs: [String] { get }
}
