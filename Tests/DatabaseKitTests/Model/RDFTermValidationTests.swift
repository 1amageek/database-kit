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

    @Test("Untyped RDF terms are admitted through role validation")
    func untypedTermsRequireRoleValidation() throws {
        let subject = RDFTerm.blankNode(
            try RDFBlankNodeIdentifier("subject")
        )
        let predicate = RDFTerm.iri(try RDFIRI("urn:predicate"))
        let object = RDFTerm.literal(
            RDFLiteral(
                lexicalForm: "value",
                datatype: .xsdString
            )
        )
        let graph = RDFTerm.iri(try RDFIRI("urn:graph"))

        let triple = try RDFTriple(
            validatingSubject: subject,
            predicate: predicate,
            object: object
        )
        let quad = try RDFQuad(
            validatingSubject: subject,
            predicate: predicate,
            object: object,
            graph: graph
        )

        #expect(triple.subject == .blankNode(
            try RDFBlankNodeIdentifier("subject")
        ))
        #expect(quad.predicate == RDFPredicateIRI(
            try RDFIRI("urn:predicate")
        ))
        let expectedGraph = try RDFGraphName(graph)
        #expect(quad.graph == expectedGraph)
    }

    @Test("Untyped RDF terms reject invalid semantic roles")
    func untypedTermsRejectInvalidRoles() throws {
        let iri = RDFTerm.iri(try RDFIRI("urn:value"))
        let literal = RDFTerm.literal(
            RDFLiteral(
                lexicalForm: "value",
                datatype: .xsdString
            )
        )

        #expect(throws: RDFDatasetValidationError.invalidSubject(literal)) {
            try RDFTriple(
                validatingSubject: literal,
                predicate: iri,
                object: iri
            )
        }
        #expect(throws: RDFDatasetValidationError.invalidPredicate(literal)) {
            try RDFTriple(
                validatingSubject: iri,
                predicate: literal,
                object: iri
            )
        }
        #expect(throws: RDFDatasetValidationError.invalidGraphName(literal)) {
            try RDFQuad(
                validatingSubject: iri,
                predicate: iri,
                object: iri,
                graph: literal
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
