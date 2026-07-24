import DatabaseTypes
import DatabaseValue
import Testing

@Suite("Database text")
struct DatabaseTextTests {
    @Test("Search is exact over UTF-8 and supports borrowed substrings")
    func exactSearch() {
        let value = "prefix/é/suffix"
        let borrowed = value[value.index(value.startIndex, offsetBy: 7)...]

        #expect(DatabaseText.contains("é", in: value))
        #expect(DatabaseText.contains("é", in: borrowed))
        #expect(!DatabaseText.contains("e\u{301}", in: value))

        let range = DatabaseText.firstRange(of: "/", in: borrowed)
        #expect(range.map { borrowed[$0] } == "/")
    }

    @Test("Replacement handles adjacent matches with one output value")
    func replacement() {
        #expect(
            DatabaseText.replacingOccurrences(
                in: "a....b",
                of: "..",
                with: "separator"
            ) == "aseparatorseparatorb"
        )
        #expect(
            DatabaseText.replacingOccurrences(
                in: "field.nested.value",
                of: ".",
                with: "_"
            ) == "field_nested_value"
        )
        #expect(
            DatabaseText.replacingOccurrences(
                in: "é",
                of: "e\u{301}",
                with: "x"
            ) == "é"
        )
    }

    @Test("Empty search starts at the borrowed view boundary")
    func emptyPattern() {
        let value = "prefix-value"
        let borrowed = value.dropFirst(7)
        let range = DatabaseText.firstRange(of: "", in: borrowed)

        #expect(range?.lowerBound == borrowed.startIndex)
        #expect(range?.isEmpty == true)
    }

    @Test("ASCII case comparison does not apply locale or Unicode folding")
    func asciiCaseComparison() {
        #expect(DatabaseText.isEqualIgnoringASCIICase("Header", "hEADER"))
        #expect(!DatabaseText.isEqualIgnoringASCIICase("straße", "STRASSE"))
        #expect(!DatabaseText.isEqualIgnoringASCIICase("é", "É"))
    }
}
