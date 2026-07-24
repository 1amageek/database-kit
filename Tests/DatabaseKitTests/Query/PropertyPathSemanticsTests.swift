import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Property path semantics")
struct PropertyPathSemanticsTests {
    @Test("Sequence and alternative builders require a first path by type")
    func buildersPreserveOrder() throws {
        let first = PropertyPath.iri(try RDFPredicateIRI("urn:first"))
        let second = PropertyPath.iri(try RDFPredicateIRI("urn:second"))
        let third = PropertyPath.iri(try RDFPredicateIRI("urn:third"))

        #expect(PropertyPath.seq(first) == first)
        #expect(
            PropertyPath.seq(first, second, third)
                == .sequence(.sequence(first, second), third)
        )
        #expect(PropertyPath.alt(first) == first)
        #expect(
            PropertyPath.alt(first, second, third)
                == .alternative(.alternative(first, second), third)
        )
    }

    @Test("Simplification preserves alternative bag multiplicity")
    func simplificationPreservesAlternativeBagMultiplicity() throws {
        let predicate = try RDFPredicateIRI(
            "https://example.invalid/property/repeated-alternative"
        )
        let path = PropertyPath.alternative(
            .iri(predicate),
            .iri(predicate)
        )

        #expect(path.simplified() == path)
    }
}
