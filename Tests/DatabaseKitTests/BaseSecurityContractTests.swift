#if DATABASE_KIT_MULTI_BASE
import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Base and security semantic contracts")
struct BaseSecurityContractTests {
    @Test("Base identifiers enforce the canonical ASCII slug grammar")
    func baseIdentifierGrammar() throws {
        #expect(try Base.ID("company-a.shared-2").value == "company-a.shared-2")

        #expect(throws: BaseIdentifierError.self) { try Base.ID("") }
        #expect(throws: BaseIdentifierError.self) { try Base.ID("Company") }
        #expect(throws: BaseIdentifierError.self) { try Base.ID("company/a") }
        #expect(throws: BaseIdentifierError.self) { try Base.ID("company..a") }
        #expect(throws: BaseIdentifierError.self) { try Base.ID("-company") }
        #expect(throws: BaseIdentifierError.self) { try Base.ID("company-") }
        #expect(throws: BaseIdentifierError.self) {
            try Base.ID(String(repeating: "a", count: 129))
        }
    }

    @Test("Composition membership is nonempty, unique, and canonically ordered")
    func compositionMembership() throws {
        let companyA = try Base.ID("company-a")
        let companyB = try Base.ID("company-b")
        let composition = try Base.Composition(
            id: Base.Composition.ID("shared"),
            bases: [companyB, companyA]
        )

        #expect(composition.bases == [companyA, companyB])
        #expect(throws: BaseCompositionError.empty) {
            try Base.Composition(
                id: Base.Composition.ID("empty"),
                bases: []
            )
        }
        #expect(throws: BaseCompositionError.duplicateBase(companyA)) {
            try Base.Composition(
                id: Base.Composition.ID("duplicate"),
                bases: [companyA, companyA]
            )
        }
    }

    @Test("Security access bits remain independent and composable")
    func securityAccessBits() {
        let readWrite: Security.Access = [.read, .write]

        #expect(readWrite.contains(.read))
        #expect(readWrite.contains(.write))
        #expect(!readWrite.contains(.administer))
        #expect(Security.Access.all == [.read, .write, .administer])
        #expect(Security.Access(rawValue: 0x80).containsOnlyKnownPermissions == false)
    }

    @Test("Entity addresses qualify identical identities by Base")
    func entityAddressQualification() throws {
        let entity = try EntityReference(entity: "Person", id: .string("alice"))
        let companyA = EntityAddress(
            baseID: try Base.ID("company-a"),
            entity: entity
        )
        let companyB = EntityAddress(
            baseID: try Base.ID("company-b"),
            entity: entity
        )

        #expect(companyA != companyB)
        #expect(companyA < companyB)
    }
}
#endif
