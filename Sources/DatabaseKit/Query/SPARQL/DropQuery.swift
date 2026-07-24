/// SPARQL DROP operation payload.
public struct DropQuery: Sendable, Equatable, Hashable {
    public let target: SPARQLGraphTarget
    public let silent: Bool

    public init(target: SPARQLGraphTarget, silent: Bool = false) {
        self.target = target
        self.silent = silent
    }
}
