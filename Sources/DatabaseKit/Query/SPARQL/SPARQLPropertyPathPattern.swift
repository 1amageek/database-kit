/// One property-path pattern inside a SPARQL basic graph pattern.
public struct SPARQLPropertyPathPattern: Sendable, Equatable, Hashable {
    public let subject: SPARQLTerm
    public let path: PropertyPath
    public let object: SPARQLTerm

    public init(
        subject: SPARQLTerm,
        path: PropertyPath,
        object: SPARQLTerm
    ) {
        self.subject = subject
        self.path = path
        self.object = object
    }
}
