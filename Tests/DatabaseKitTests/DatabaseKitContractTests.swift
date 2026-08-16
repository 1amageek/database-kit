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
        try RDFTermValidation.validate(term, role: .predicate)
        let budget = ExecutionBudget(
            maximumRows: 25,
            maximumWorkUnits: 50,
            maximumIntermediateRows: 10,
            maximumIntermediateBytes: 1_024,
            timeoutMilliseconds: 500
        )
        let fingerprintBytes = ByteString(
            repeating: 0xA5,
            count: SchemaFingerprint.byteCount
        )
        let fingerprint = try SchemaFingerprint(fingerprintBytes)

        #expect(version.description == "1.0.0")
        #expect(path.predicateIRI == predicate)
        #expect(budget.maximumRows == 25)
        #expect(fingerprint.bytes == fingerprintBytes)
        #expect(
            throws: SchemaFingerprintError.invalidByteCount(
                actual: SchemaFingerprint.byteCount - 1,
                expected: SchemaFingerprint.byteCount
            )
        ) {
            try SchemaFingerprint(
                ByteString(
                    repeating: 0,
                    count: SchemaFingerprint.byteCount - 1
                )
            )
        }
    }
}
