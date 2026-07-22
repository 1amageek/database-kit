/// The mutation performed by a SPARQL graph transfer operation.
public enum SPARQLGraphTransferOperation: Sendable, Equatable, Hashable {
    case add
    case copy
    case move
}
