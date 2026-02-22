/// Marker macro that binds a field to an OWL DatatypeProperty.
///
/// Namespace is auto-resolved from the `@OWLClass` IRI.
/// Accepts local names, CURIEs, and full IRIs.
///
/// DataProperty (value property):
/// ```swift
/// @OWLClass("ex:Employee")
/// struct Employee {
///     @OWLDataProperty("name")       // → "ex:name"
///     var name: String
///
///     @OWLDataProperty("foaf:mbox")  // → "foaf:mbox" (CURIE kept as-is)
///     var email: String
/// }
/// ```
///
/// ObjectProperty reference (with reverse index):
/// ```swift
/// @OWLDataProperty("worksFor", to: \Department.id)  // → "ex:worksFor"
/// var departmentID: String?
/// ```
///
/// When `to:` is specified, `@Persistable` automatically generates a reverse index.
@attached(peer)
public macro OWLDataProperty(
    _ iri: String,
    label: String? = nil
) = #externalMacro(module: "GraphMacros", type: "OWLDataPropertyMacro")

/// ObjectProperty reference variant: `to:` specifies the target field
@attached(peer)
public macro OWLDataProperty(
    _ iri: String,
    label: String? = nil,
    to keyPath: AnyKeyPath
) = #externalMacro(module: "GraphMacros", type: "OWLDataPropertyMacro")

/// Backward compatibility
@available(*, deprecated, renamed: "OWLDataProperty")
@attached(peer)
public macro OWLProperty(
    _ iri: String,
    label: String? = nil
) = #externalMacro(module: "GraphMacros", type: "OWLDataPropertyMacro")

/// Backward compatibility
@available(*, deprecated, renamed: "OWLDataProperty")
@attached(peer)
public macro OWLProperty(
    _ iri: String,
    label: String? = nil,
    to keyPath: AnyKeyPath
) = #externalMacro(module: "GraphMacros", type: "OWLDataPropertyMacro")
