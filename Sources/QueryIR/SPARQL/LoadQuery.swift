/// SPARQL LOAD operation payload.
public struct LoadQuery: Sendable, Equatable, Hashable {
    public let source: String
    public let destination: String?
    public let silent: Bool

    public init(source: String, destination: String? = nil, silent: Bool = false) {
        self.source = source
        self.destination = destination
        self.silent = silent
    }
}
