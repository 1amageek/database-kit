/// A graph-store target shared by SPARQL CLEAR and DROP.
public enum SPARQLGraphTarget: Sendable, Equatable, Hashable {
    case graph(String)
    case `default`
    case named
    case all
}
