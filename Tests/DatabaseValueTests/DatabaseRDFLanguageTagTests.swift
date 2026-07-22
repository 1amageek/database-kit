import DatabaseValue
import Testing

@Suite("RDF language-tag model")
struct DatabaseRDFLanguageTagTests {
    @Test("BCP 47 well-formed tags are accepted and canonicalized")
    func wellFormedTags() throws {
        let values = [
            "en",
            "EN-Latn-US",
            "zh-min-nan",
            "x-private-1",
            "en-Latn-US-u-ca-gregory-x-private",
        ]

        for value in values {
            let tag = try DatabaseRDFLanguageTag(value)
            #expect(tag.rawValue == value.lowercased())
        }
    }

    @Test("malformed language tags fail at construction")
    func malformedTags() {
        let values = [
            "",
            "en-",
            "-en",
            "en_US",
            "x",
            "en-a",
            "en-abcdefghi",
            "12",
            "日本語",
            "de-1901-1901",
            "en-abcde-abcde",
            "en-a-foo-a-bar",
        ]

        for value in values {
            #expect(throws: DatabaseRDFLanguageTagError.self) {
                _ = try DatabaseRDFLanguageTag(value)
            }
        }
    }

    @Test("language and direction determine the only legal RDF annotations")
    func literalAnnotations() throws {
        let language = try DatabaseRDFLanguageTag("AR")
        let tagged = DatabaseRDFLiteral(
            lexicalForm: "مرحبا",
            language: language
        )
        let directional = DatabaseRDFLiteral(
            lexicalForm: "مرحبا",
            language: language,
            direction: .rightToLeft
        )

        #expect(tagged.datatypeIRI == .rdfLanguageString)
        #expect(tagged.language == "ar")
        #expect(tagged.direction == nil)
        #expect(directional.datatypeIRI == .rdfDirectionalLanguageString)
        #expect(directional.language == "ar")
        #expect(directional.direction == "rtl")
    }

    @Test("reserved language datatypes cannot form ordinary typed literals")
    func reservedDatatypeInvariants() throws {
        #expect(
            throws: DatabaseRDFTypedLiteralDatatypeError
                .languageDatatypeRequiresLanguage
        ) {
            _ = try DatabaseRDFTypedLiteralDatatype(.rdfLanguageString)
        }
        #expect(
            throws: DatabaseRDFTypedLiteralDatatypeError
                .directionalLanguageDatatypeRequiresLanguageAndDirection
        ) {
            _ = try DatabaseRDFTypedLiteralDatatype(
                .rdfDirectionalLanguageString
            )
        }
    }
}
