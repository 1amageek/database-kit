/// SPARQL DELETE WHERE operation payload.
///
/// The quad pattern is stored once so the delete template and WHERE pattern
/// cannot diverge. Execution derives both roles from this canonical value.
public struct DeleteWhereQuery: Sendable, Equatable, Hashable {
    public let pattern: [Quad]

    public init(pattern: consuming [Quad]) {
        self.pattern = consume pattern
    }
}
