import DatabaseValue
import QueryIR
import Testing

@Suite("QueryIR property-path semantics")
struct QueryIRPropertyPathSemanticsTests {
    @Test("Simplification preserves alternative bag multiplicity")
    func simplificationPreservesAlternativeBagMultiplicity() throws {
        let predicate = try DatabaseRDFPredicateIRI(
            "https://example.invalid/property/repeated-alternative"
        )
        let path = PropertyPath.alternative(
            .iri(predicate),
            .iri(predicate)
        )

        #expect(path.simplified() == path)
    }
}
