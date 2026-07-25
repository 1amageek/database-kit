import DatabaseTypes
@testable import DatabaseKit
import Testing

@Suite("Database text")
struct UTF8TextTests {
    @Test("Search is exact over UTF-8 and supports borrowed substrings")
    func exactSearch() {
        let value = "prefix/é/suffix"
        let borrowed = value[value.index(value.startIndex, offsetBy: 7)...]

        #expect(UTF8Text.contains("é", in: value))
        #expect(UTF8Text.contains("é", in: borrowed))
        #expect(!UTF8Text.contains("e\u{301}", in: value))

        let range = UTF8Text.firstRange(of: "/", in: borrowed)
        #expect(range.map { borrowed[$0] } == "/")
    }

    @Test("Empty search starts at the borrowed view boundary")
    func emptyPattern() {
        let value = "prefix-value"
        let borrowed = value.dropFirst(7)
        let range = UTF8Text.firstRange(of: "", in: borrowed)

        #expect(range?.lowerBound == borrowed.startIndex)
        #expect(range?.isEmpty == true)
    }

    @Test("ASCII case comparison does not apply locale or Unicode folding")
    func asciiCaseComparison() {
        #expect(UTF8Text.isEqualIgnoringASCIICase("Header", "hEADER"))
        #expect(!UTF8Text.isEqualIgnoringASCIICase("straße", "STRASSE"))
        #expect(!UTF8Text.isEqualIgnoringASCIICase("é", "É"))
    }
}
