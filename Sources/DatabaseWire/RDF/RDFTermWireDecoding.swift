import DatabaseTypes

/// A decoded RDF term together with the resources consumed by its canonical form.
struct RDFTermWireDecoding: Sendable {
    let term: RDFTerm
    let objectCount: Int
    let maximumDepth: Int

    init(
        term: RDFTerm,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.term = term
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
