import DatabaseTypes
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
/// @OWLClass(
///     "http://example.org/onto#Employee",
///     individualIRIBase: "http://example.org/individual/"
/// )
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
/// @OWLClass(
///     "https://example.org/ontology/Person",
///     individualIRIBase: "https://example.org/individual/",
///     graph: "https://example.org/graph/people"
/// )
/// struct Person { ... }
/// ```
///
/// **Generated code**:
/// - `static var ontologyClassIRI: String` — OWL class IRI
/// - `static var ontologyPropertyDescriptors: [OWLDataPropertyDescriptor]` — metadata for `@OWLDataProperty` fields
/// - `OWLClassEntity` protocol conformance
/// - canonical RDF dataset projection metadata
///
/// - Parameters:
///   - iri: OWL class IRI.
///   - individualIRIBase: Absolute base IRI for materialized individuals.
///   - graph: Optional named graph IRI. `nil` selects the default graph.
@attached(
    member,
    names: named(ontologyClassIRI), named(ontologyPropertyDescriptors),
        named(ontologyIndividualIRIBase), named(ontologyGraph),
        named(ontologySubject), named(ontologyQuads), named(_owlRDFDescriptors),
        named(_owlRDFIndexDescriptors)
)
@attached(extension, conformances: OWLClassEntity)
public macro OWLClass(
    _ iri: String,
    individualIRIBase: String,
    graph: String? = nil
) = #externalMacro(module: "GraphMacros", type: "OWLClassMacro")
