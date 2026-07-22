import DatabaseValue
import DatabaseWire
import Testing

@Suite("Database RDF term wire boundaries")
struct DatabaseRDFTermWireBoundaryTests {
    @Test("wire encoding rejects invalid RDF state")
    func invalidEncodeState() {
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidIRI(.missingScheme)
            )
        ) {
            _ = try encodeTerm(.iri("relative"))
        }
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidTriplePredicate
            )
        ) {
            _ = try encodeTerm(
                .tripleTerm(
                    subject: .iri("urn:subject"),
                    predicate: .blankNode("predicate"),
                    object: .iri("urn:object")
                )
            )
        }
    }

    @Test("wire decoding rejects invalid RDF state")
    func invalidDecodeState() {
        var reader = DatabaseWireReader(DatabaseBytes([
            5, 0, 0, 0,
            2, 4, 0x62, 0x61, 0x64,
        ]))

        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidIRI(.missingScheme)
            )
        ) {
            _ = try DatabaseRDFTerm(from: &reader)
        }
    }

    @Test("wire RDF payload is exactly the canonical term representation")
    func wireUsesCanonicalTermEncoding() throws {
        let term = DatabaseRDFTerm.literal(DatabaseRDFLiteral(
            lexicalForm: "before\0after",
            language: try DatabaseRDFLanguageTag("ja")
        ))
        let canonical = try DatabaseRDFTermCodec.encode(term)
        let wire = try encodeTerm(term)
        var expected = [
            UInt8(truncatingIfNeeded: canonical.count),
            UInt8(truncatingIfNeeded: canonical.count >> 8),
            UInt8(truncatingIfNeeded: canonical.count >> 16),
            UInt8(truncatingIfNeeded: canonical.count >> 24),
        ]
        expected.append(contentsOf: canonical)

        #expect(wire == DatabaseBytes(expected))
    }

    @Test("wire encoding applies depth and object budgets")
    func encodeBudgets() throws {
        let leaf = DatabaseRDFTerm.iri("urn:leaf")
        let nested = DatabaseRDFTerm.tripleTerm(
            subject: .iri("urn:subject"),
            predicate: .iri("urn:predicate"),
            object: .tripleTerm(
                subject: .blankNode("inner"),
                predicate: .iri("urn:inner-predicate"),
                object: leaf
            )
        )
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 1_024,
            maximumStringBytes: 1_024,
            maximumByteStringBytes: 1_024,
            maximumCollectionCount: 100,
            maximumNestingDepth: 1,
            maximumObjectCount: 100
        )

        #expect(
            throws: DatabaseWireError.nestingTooDeep(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try encodeTerm(nested, limits: limits)
        }
    }

    @Test("quad construction validates every RDF role")
    func quadRoleValidation() {
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidRole(expected: .subject, actual: .literal)
            )
        ) {
            _ = try DatabaseRDFQuad(
                subject: .literal(DatabaseRDFLiteral(
                    lexicalForm: "invalid",
                    datatype: .xsdString
                )),
                predicate: .iri("urn:predicate"),
                object: .iri("urn:object")
            )
        }
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidRole(expected: .predicate, actual: .blankNode)
            )
        ) {
            _ = try DatabaseRDFQuad(
                subject: .iri("urn:subject"),
                predicate: .blankNode("invalid"),
                object: .iri("urn:object")
            )
        }
    }

    private func encodeTerm(
        _ term: DatabaseRDFTerm,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> DatabaseBytes {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try term.encode(into: &writer)
        }
    }
}
