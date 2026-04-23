/// Macro that binds a Persistable type to an OWL class in the OntologyStore.
///
/// Generates `OWLClassEntity` protocol conformance, adding
/// `ontologyClassIRI` and `ontologyPropertyDescriptors` to the type.
///
/// **Design principle**: Macros are bindings, not definitions.
/// - Class definitions, property characteristics, and axioms live in OntologyStore
/// - This macro declares which OntologyStore concept a Swift type corresponds to
///
/// **Usage**:
/// ```swift
/// @Persistable
/// @OWLClass("http://example.org/onto#Employee")
/// struct Employee {
///     @OWLDataProperty("http://example.org/onto#name")
///     var name: String
///
///     @OWLDataProperty("http://example.org/onto#worksFor", to: \Department.id)
///     var departmentID: String?
/// }
///
/// // Bind materialized triples to a named graph:
/// @Persistable
/// @OWLClass("ex:Person", graph: "memory:default")
/// struct Person { ... }
/// ```
///
/// **Generated code**:
/// - `static var ontologyClassIRI: String` — OWL class IRI
/// - `static var ontologyPropertyDescriptors: [OWLDataPropertyDescriptor]` — metadata for `@OWLDataProperty` fields
/// - `OWLClassEntity` protocol conformance
///
/// - Parameters:
///   - iri: OWL class IRI (CURIE like `"ex:Person"` or full IRI).
///   - graph: Named graph IRI the materialized triples are written to. Defaults
///     to `"default"` for backward compatibility; pass a specific graph (e.g.
///     `"memory:default"`) when federating with `sparql(graph:)`.
@attached(member, names: named(ontologyClassIRI), named(ontologyPropertyDescriptors), named(_owlTripleDescriptors))
@attached(extension, conformances: OWLClassEntity)
public macro OWLClass(_ iri: String, graph: String = "default") = #externalMacro(module: "GraphMacros", type: "OWLClassMacro")

/// Backward compatibility
@available(*, deprecated, renamed: "OWLClass")
@attached(member, names: named(ontologyClassIRI), named(ontologyPropertyDescriptors), named(_owlTripleDescriptors))
@attached(extension, conformances: OWLClassEntity)
public macro Ontology(_ iri: String, graph: String = "default") = #externalMacro(module: "GraphMacros", type: "OWLClassMacro")
