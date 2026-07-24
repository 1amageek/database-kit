import DatabaseTypes
import DatabaseValue
import DatabaseWire
import Testing

@Suite("Database RDF term wire boundaries")
struct DatabaseRDFTermWireBoundaryTests {
    @Test("wire decoding rejects invalid RDF state")
    func invalidDecodeState() {
        var reader = DatabaseWireReader(ByteString([
            5, 0, 0, 0,
            2, 4, 0x62, 0x61, 0x64,
        ]))

        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidIRI(.missingScheme)
            )
        ) {
            _ = try RDFTerm(from: &reader)
        }
    }

    @Test("wire RDF payload is exactly the canonical term representation")
    func wireUsesCanonicalTermEncoding() throws {
        let term = RDFTerm.literal(RDFLiteral(
            lexicalForm: "before\0after",
            language: try RDFLanguageTag("ja")
        ))
        let canonical = try RDFTermCodec.encode(term)
        let wire = try encodeTerm(term)
        var expected = [
            UInt8(truncatingIfNeeded: canonical.count),
            UInt8(truncatingIfNeeded: canonical.count >> 8),
            UInt8(truncatingIfNeeded: canonical.count >> 16),
            UInt8(truncatingIfNeeded: canonical.count >> 24),
        ]
        expected.append(contentsOf: canonical)

        #expect(wire == ByteString(expected))
    }

    @Test("wire encoding applies depth and object budgets")
    func encodeBudgets() throws {
        let leaf = RDFTerm.iri(try RDFIRI("urn:leaf"))
        let nested = RDFTerm.tripleTerm(
            subject: .iri(try RDFIRI("urn:subject")),
            predicate: try RDFPredicateIRI("urn:predicate"),
            object: .tripleTerm(
                subject: .blankNode(
                    try RDFBlankNodeIdentifier("inner")
                ),
                predicate: try RDFPredicateIRI(
                    "urn:inner-predicate"
                ),
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
    func quadRoleValidation() throws {
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidRole(expected: .subject, actual: .literal)
            )
        ) {
            _ = try DatabaseRDFQuad(
                subject: .literal(RDFLiteral(
                    lexicalForm: "invalid",
                    datatype: .xsdString
                )),
                predicate: .iri(try RDFIRI("urn:predicate")),
                object: .iri(try RDFIRI("urn:object"))
            )
        }
        #expect(
            throws: DatabaseWireError.invalidCanonicalRDFTerm(
                .invalidRole(expected: .predicate, actual: .blankNode)
            )
        ) {
            _ = try DatabaseRDFQuad(
                subject: .iri(try RDFIRI("urn:subject")),
                predicate: .blankNode(
                    try RDFBlankNodeIdentifier("invalid")
                ),
                object: .iri(try RDFIRI("urn:object"))
            )
        }
    }

    private func encodeTerm(
        _ term: RDFTerm,
        limits: DatabaseWireLimits = .default
    ) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) -> Void in
            try term.encode(into: &writer)
        }
    }
}
