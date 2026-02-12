import Foundation

extension Schema {

    /// Type-erased, Codable representation of an ontology.
    ///
    /// Follows the `AnyIndexDescriptor` pattern: Core stores opaque encoded data
    /// without knowing the concrete ontology type (e.g., `OWLOntology` in Graph module).
    ///
    /// - `iri`: Ontology IRI identifier
    /// - `typeIdentifier`: Concrete type name for decoding (e.g., `"OWLOntology"`)
    /// - `encodedData`: JSON-encoded concrete ontology
    ///
    /// **Usage**:
    /// ```swift
    /// // Graph module — encode
    /// let schemaOntology = owlOntology.asSchemaOntology()
    ///
    /// // Core module — pass through
    /// let schema = Schema([User.self], ontology: schemaOntology)
    ///
    /// // GraphIndex module — decode
    /// let owlOntology = try OWLOntology(schemaOntology: schema.ontology!)
    /// ```
    public struct Ontology: Sendable, Codable, Hashable {

        /// Ontology IRI (identifier)
        public let iri: String

        /// Concrete type identifier (e.g., "OWLOntology")
        ///
        /// Used to select the correct decoder when restoring the concrete type.
        public let typeIdentifier: String

        /// JSON-encoded ontology data
        ///
        /// Contains the full concrete ontology serialized via `JSONEncoder`.
        /// Core module does not interpret this data.
        public let encodedData: Data

        public init(iri: String, typeIdentifier: String, encodedData: Data) {
            self.iri = iri
            self.typeIdentifier = typeIdentifier
            self.encodedData = encodedData
        }
    }
}
