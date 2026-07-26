import DatabaseKit
import DatabaseTypes
import Testing

@Suite("RDF term validation")
struct RDFTermValidationTests {
    @Test("RDF roles accept only their semantic term kinds")
    func rolesEnforceSemanticKinds() throws {
        let iri = RDFTerm.iri(try RDFIRI("urn:predicate"))
        let literal = RDFTerm.literal(RDFLiteral(
            lexicalForm: "value",
            datatype: try RDFTypedLiteralDatatype(
                RDFIRI("http://www.w3.org/2001/XMLSchema#string")
            )
        ))

        try RDFTermValidation.validate(iri, role: .predicate)
        try RDFTermValidation.validate(literal, role: .object)
        #expect(throws: RDFTermValidationError.invalidRole(
            expected: .subject,
            actual: .literal
        )) {
            try RDFTermValidation.validate(literal, role: .subject)
        }
    }

    @Test("Depth and term-count limits reject the exact first excess")
    func resourceLimitsRejectFirstExcess() throws {
        let nested = try nestedTerm(depth: 2)

        try RDFTermValidation.validate(
            nested,
            limits: try RDFTermValidationLimits(
                maximumDepth: 2,
                maximumTermCount: 7
            )
        )
        #expect(throws: RDFTermValidationError.maximumDepthExceeded(
            actual: 2,
            maximum: 1
        )) {
            try RDFTermValidation.validate(
                nested,
                limits: try RDFTermValidationLimits(
                    maximumDepth: 1,
                    maximumTermCount: 7
                )
            )
        }
        #expect(throws: RDFTermValidationError.maximumTermCountExceeded(
            actual: 7,
            maximum: 6
        )) {
            try RDFTermValidation.validate(
                nested,
                limits: try RDFTermValidationLimits(
                    maximumDepth: 2,
                    maximumTermCount: 6
                )
            )
        }
    }

    @Test("Invalid resource limits fail explicitly")
    func invalidLimitsFailExplicitly() {
        #expect(throws: RDFTermValidationLimitsError.negativeMaximumDepth(-1)) {
            try RDFTermValidationLimits(
                maximumDepth: -1,
                maximumTermCount: 1
            )
        }
        #expect(
            throws: RDFTermValidationLimitsError
                .nonPositiveMaximumTermCount(0)
        ) {
            try RDFTermValidationLimits(
                maximumDepth: 0,
                maximumTermCount: 0
            )
        }
    }

    private func nestedTerm(depth: Int) throws -> RDFTerm {
        var term = RDFTerm.iri(try RDFIRI("urn:leaf"))
        for index in 0..<depth {
            term = .tripleTerm(
                subject: .iri(try RDFIRI("urn:subject:\(index)")),
                predicate: RDFPredicateIRI(
                    try RDFIRI("urn:predicate:\(index)")
                ),
                object: term
            )
        }
        return term
    }
}
