import DatabaseTypes

/// A decoded RDF term together with the resources consumed by its canonical form.
public struct RDFTermDecodingResult: Sendable {
    public let term: RDFTerm
    public let objectCount: Int
    public let maximumDepth: Int

    package init(
        term: RDFTerm,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.term = term
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
