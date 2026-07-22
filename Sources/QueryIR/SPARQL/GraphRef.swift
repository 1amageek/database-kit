/// A graph reference in a SPARQL USING clause.
public struct GraphRef: Sendable, Equatable, Hashable {
    public let iri: String
    public let isNamed: Bool

    public init(iri: String, isNamed: Bool = false) {
        self.iri = iri
        self.isNamed = isNamed
    }
}
