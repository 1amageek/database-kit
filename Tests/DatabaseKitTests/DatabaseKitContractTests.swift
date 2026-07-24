import DatabaseKit
import DatabaseTypes
import Testing

@Suite("DatabaseKit semantic contracts")
struct DatabaseKitContractTests {
    @Test("Shared contracts retain their domain invariants")
    func sharedContractsRetainDomainInvariants() throws {
        let version = SchemaVersion(1, 0, 0)
        let predicate = try RDFPredicateIRI("urn:calendar:event")
        let path = SHACLPath.predicate(predicate)
        let term = RDFTerm.iri(try RDFIRI("urn:calendar:event"))
        let encoded = try RDFTermCodec.encode(term)

        #expect(version.description == "1.0.0")
        #expect(path.predicateIRI == predicate)
        #expect(
            try RDFTermCodec.decode(encoded) == term
        )
    }
}
