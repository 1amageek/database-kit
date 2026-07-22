/// A decoded RDF term together with the resources consumed by its canonical form.
public struct DatabaseRDFTermDecodingResult: Sendable {
    public let term: DatabaseRDFTerm
    public let objectCount: Int
    public let maximumDepth: Int

    package init(
        term: DatabaseRDFTerm,
        objectCount: Int,
        maximumDepth: Int
    ) {
        self.term = term
        self.objectCount = objectCount
        self.maximumDepth = maximumDepth
    }
}
