/// Internal bridge protocol for runtime access to OWL class IRI.
///
/// Allows `Schema.Entity` (in Core) to extract ontology metadata
/// without a circular dependency on the Graph module.
/// Graph's `OWLClassEntity` conforms to this protocol.
public protocol _OntologyClassIRIProvider {
    static var ontologyClassIRI: String { get }
}

/// Internal bridge protocol for runtime access to OWL ObjectProperty metadata.
///
/// Allows `Schema.Entity` (in Core) to extract ObjectProperty info
/// without a circular dependency on the Graph module.
/// Graph's `OWLObjectPropertyEntity` conforms to this protocol.
public protocol _ObjectPropertyIRIProvider {
    static var objectPropertyIRI: String { get }
    static var fromFieldName: String { get }
    static var toFieldName: String { get }
}
