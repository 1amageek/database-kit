/// SPARQL ADD, COPY, or MOVE operation payload.
public struct GraphTransferQuery: Sendable, Equatable, Hashable {
    public let operation: SPARQLGraphTransferOperation
    public let source: SPARQLGraphTransferEndpoint
    public let destination: SPARQLGraphTransferEndpoint
    public let silent: Bool

    public init(
        operation: SPARQLGraphTransferOperation,
        source: SPARQLGraphTransferEndpoint,
        destination: SPARQLGraphTransferEndpoint,
        silent: Bool = false
    ) {
        self.operation = operation
        self.source = source
        self.destination = destination
        self.silent = silent
    }
}
