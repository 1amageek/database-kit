/// SPARQL DELETE DATA operation payload.
public struct DeleteDataQuery: Sendable, Equatable, Hashable {
    public let quads: [Quad]

    public init(quads: consuming [Quad]) {
        self.quads = consume quads
    }
}
