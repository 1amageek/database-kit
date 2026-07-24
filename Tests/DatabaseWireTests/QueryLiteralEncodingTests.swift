import DatabaseTypes
import DatabaseValue
import QueryIR
import Testing

@Suite("Database Literal Encoding")
struct QueryLiteralEncodingTests {
    @Test func hexadecimalUsesCanonicalUppercaseDigits() {
        #expect(QueryLiteralEncoding.hex([0x00, 0x0F, 0x10, 0xFF]) == "000F10FF")
    }

    @Test func base64UsesCanonicalPadding() {
        #expect(QueryLiteralEncoding.base64([]) == "")
        #expect(QueryLiteralEncoding.base64([0x00]) == "AA==")
        #expect(QueryLiteralEncoding.base64([0x00, 0x01]) == "AAE=")
        #expect(QueryLiteralEncoding.base64([0x00, 0x01, 0x02]) == "AAEC")
        #expect(QueryLiteralEncoding.base64([0xFB, 0xFF, 0xFF]) == "+///")
    }
}
