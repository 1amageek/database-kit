/// The resources selected by a SPARQL DESCRIBE query.
///
/// Explicit resources are structurally non-empty so `DESCRIBE *` can never be
/// confused with an empty resource array.
public enum DescribeSelection: Sendable, Equatable, Hashable {
    case all
    case resources(first: SPARQLTerm, additional: [SPARQLTerm])
}
