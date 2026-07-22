/// SPARQL CREATE GRAPH operation payload.
public struct CreateSPARQLGraphQuery: Sendable, Equatable, Hashable {
    public let graph: String
    public let silent: Bool

    public init(graph: String, silent: Bool = false) {
        self.graph = graph
        self.silent = silent
    }
}
