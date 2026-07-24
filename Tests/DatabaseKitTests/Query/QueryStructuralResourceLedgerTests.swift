import DatabaseKit
import Testing

@Suite("Query structural resource ledger")
struct QueryStructuralResourceLedgerTests {
    @Test("nesting admission must be balanced")
    func nestingAdmissionMustBeBalanced() throws {
        var ledger = QueryStructuralResourceLedger()

        #expect(throws: QueryStructuralValidationError.unbalancedNesting) {
            try ledger.leaveNesting()
        }

        try ledger.enterNesting()
        try ledger.leaveNesting()
    }

    @Test("nesting depth cannot use accumulated resource admission")
    func nestingDepthCannotUseAccumulatedResourceAdmission() {
        var ledger = QueryStructuralResourceLedger()

        #expect(
            throws: QueryStructuralValidationError.invalidResourceClaim(
                .nestingDepth
            )
        ) {
            try ledger.consume(.nestingDepth)
        }
    }
}
