/// The template action of a SPARQL Modify operation.
///
/// Every case contains at least one syntactic DELETE or INSERT clause, so the
/// invalid state in which both clauses are absent cannot be represented.
public enum SPARQLModifyAction: Sendable, Equatable, Hashable {
    case delete([Quad])
    case insert([Quad])
    case deleteAndInsert(delete: [Quad], insert: [Quad])
}
