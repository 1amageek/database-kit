import DatabaseValue
import Testing

@Suite("RDF term identity")
struct DatabaseRDFIdentityTests {
    private let composed = "é"
    private let decomposed = "e\u{301}"

    @Test("Literal identity preserves the exact Unicode scalar sequence")
    func literalIdentity() {
        let left = DatabaseRDFLiteral(
            lexicalForm: composed,
            datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
        )
        let right = DatabaseRDFLiteral(
            lexicalForm: decomposed,
            datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
        )

        #expect(left != right)
        #expect(Set([left, right]).count == 2)
    }

    @Test("IRI and blank-node identity is not Unicode-normalized")
    func resourceIdentity() {
        let iris: Set<DatabaseRDFTerm> = [
            .iri("https://example.com/\(composed)"),
            .iri("https://example.com/\(decomposed)"),
        ]
        let blankNodes: Set<DatabaseRDFTerm> = [
            .blankNode(composed),
            .blankNode(decomposed),
        ]

        #expect(iris.count == 2)
        #expect(blankNodes.count == 2)
    }

    @Test("Exact ordering is consistent with equality for nested RDF-star terms")
    func orderingConsistency() {
        let left = DatabaseRDFTerm.tripleTerm(
            subject: .iri("https://example.com/subject"),
            predicate: .iri("https://example.com/predicate"),
            object: .literal(DatabaseRDFLiteral(
                lexicalForm: composed,
                datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
            ))
        )
        let right = DatabaseRDFTerm.tripleTerm(
            subject: .iri("https://example.com/subject"),
            predicate: .iri("https://example.com/predicate"),
            object: .literal(DatabaseRDFLiteral(
                lexicalForm: decomposed,
                datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
            ))
        )

        #expect(left != right)
        #expect((left < right) != (right < left))
        #expect(Set([left, right]).count == 2)
    }

    @Test("RDF 1.2 language tags use ASCII case-insensitive identity")
    func languageTagIdentity() throws {
        let uppercase = DatabaseRDFLiteral(
            lexicalForm: "hello",
            language: try DatabaseRDFLanguageTag("EN-Latn-US")
        )
        let lowercase = DatabaseRDFLiteral(
            lexicalForm: "hello",
            language: try DatabaseRDFLanguageTag("en-latn-us")
        )
        let uppercaseTerm = DatabaseRDFTerm.literal(uppercase)
        let lowercaseTerm = DatabaseRDFTerm.literal(lowercase)

        #expect(uppercase == lowercase)
        #expect(uppercase.language == "en-latn-us")
        #expect(lowercase.language == "en-latn-us")
        #expect(Set([uppercase, lowercase]).count == 1)
        #expect(!(uppercaseTerm < lowercaseTerm))
        #expect(!(lowercaseTerm < uppercaseTerm))
    }

    @Test("Language-tagged lexical forms remain case-sensitive")
    func languageTaggedLexicalIdentity() throws {
        let uppercase = DatabaseRDFLiteral(
            lexicalForm: "Hello",
            language: try DatabaseRDFLanguageTag("en")
        )
        let lowercase = DatabaseRDFLiteral(
            lexicalForm: "hello",
            language: try DatabaseRDFLanguageTag("EN")
        )

        #expect(uppercase != lowercase)
        #expect(Set([uppercase, lowercase]).count == 2)
    }
}
