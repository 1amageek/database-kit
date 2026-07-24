/// SPARQL INSERT DATA operation payload.
public struct InsertDataQuery: Sendable, Equatable, Hashable {
    public let quads: [Quad]

    public init(quads: consuming [Quad]) {
        self.quads = consume quads
    }
}
