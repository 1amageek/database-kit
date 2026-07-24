/// A legal source or destination for SPARQL ADD, COPY, and MOVE.
public enum SPARQLGraphTransferEndpoint: Sendable, Equatable, Hashable {
    case `default`
    case graph(String)
}
