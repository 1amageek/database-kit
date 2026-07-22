/// A SPARQL triple pattern with an optional graph term.
public struct Quad: Sendable, Equatable, Hashable {
    public let graph: SPARQLTerm?
    public let triple: TriplePattern

    public init(graph: SPARQLTerm? = nil, triple: TriplePattern) {
        self.graph = graph
        self.triple = triple
    }
}
