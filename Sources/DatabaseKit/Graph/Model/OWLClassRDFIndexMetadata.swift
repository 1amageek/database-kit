import DatabaseTypes

/// Canonical, non-generic OWL class RDF projection metadata.
public struct OWLClassRDFIndexMetadata: Sendable, Hashable {
    public let individualIRIBase: String
    public let graph: RDFGraphName?

    public init(
        canonical kind: IndexKindMetadata
    ) throws(IndexKindMetadataError) {
        try kind.validateIdentity(
            identifier: "owl_class_rdf",
            subspaceStructure: .hierarchical
        )
        try kind.validateMetadataKeys(
            required: ["individualIRIBase"],
            optional: ["graph"]
        )
        try kind.validateFieldCount(0)
        self.individualIRIBase = try kind.requireString("individualIRIBase")
        if kind.metadata["graph"] != nil {
            let graphTerm = try kind.requireRDFTerm("graph")
            do {
                self.graph = try RDFGraphName(graphTerm)
            } catch {
                throw .invalidMetadata(
                    identifier: kind.identifier,
                    key: "graph"
                )
            }
        } else {
            self.graph = nil
        }
    }
}
