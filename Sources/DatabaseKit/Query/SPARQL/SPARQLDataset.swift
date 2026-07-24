/// The RDF dataset selected by SPARQL dataset clauses.
///
/// `implicit` delegates dataset selection to the execution context. `explicit`
/// preserves the distinction between default graphs introduced by `FROM` and
/// named graphs introduced by `FROM NAMED`.
public enum SPARQLDataset: Sendable, Equatable, Hashable {
    case implicit
    case explicit(defaultGraphs: [String], namedGraphs: [String])
}
