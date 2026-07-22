/// SPARQL Modify operation payload.
public struct SPARQLModifyOperation: Sendable, Equatable, Hashable {
    public let withGraph: String?
    public let action: SPARQLModifyAction
    public let using: [GraphRef]
    public let wherePattern: GraphPattern

    public init(
        withGraph: String? = nil,
        action: consuming SPARQLModifyAction,
        using: consuming [GraphRef] = [],
        wherePattern: consuming GraphPattern
    ) {
        self.withGraph = withGraph
        self.action = consume action
        self.using = consume using
        self.wherePattern = consume wherePattern
    }
}
