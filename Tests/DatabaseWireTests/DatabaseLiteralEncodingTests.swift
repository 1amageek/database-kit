import DatabaseValue
import QueryIR
import Testing

@Suite("Database Literal Encoding")
struct DatabaseLiteralEncodingTests {
    @Test func hexadecimalUsesCanonicalUppercaseDigits() {
        #expect(DatabaseLiteralEncoding.hex([0x00, 0x0F, 0x10, 0xFF]) == "000F10FF")
    }

    @Test func base64UsesCanonicalPadding() {
        #expect(DatabaseLiteralEncoding.base64([]) == "")
        #expect(DatabaseLiteralEncoding.base64([0x00]) == "AA==")
        #expect(DatabaseLiteralEncoding.base64([0x00, 0x01]) == "AAE=")
        #expect(DatabaseLiteralEncoding.base64([0x00, 0x01, 0x02]) == "AAEC")
        #expect(DatabaseLiteralEncoding.base64([0xFB, 0xFF, 0xFF]) == "+///")
    }
}
