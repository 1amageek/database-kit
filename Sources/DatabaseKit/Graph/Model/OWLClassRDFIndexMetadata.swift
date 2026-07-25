import DatabaseTypes

/// Canonical, non-generic OWL class RDF projection metadata.
public struct OWLClassRDFIndexMetadata: Sendable, Hashable {
    public let individualIRIBase: String
    public let graph: RDFTerm?

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
            self.graph = try kind.requireRDFTerm("graph")
        } else {
            self.graph = nil
        }
    }
}
