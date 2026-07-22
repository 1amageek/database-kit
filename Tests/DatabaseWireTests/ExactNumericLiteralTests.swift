import QueryIR
import Testing

@Suite("Exact numeric literals")
struct ExactNumericLiteralTests {
    @Test("integer parsing preserves signed and unsigned ranges")
    func integerParsing() {
        #expect(Literal.parseInteger("-9223372036854775808") == .int(Int64.min))
        #expect(Literal.parseInteger("18446744073709551615") == .uint(UInt64.max))
        #expect(Literal.parseInteger("18446744073709551616") == nil)
    }

    @Test("decimal parsing normalizes lexical forms exactly")
    func decimalParsing() {
        #expect(
            Literal.parseDecimal("00123.4500")
                == .decimal(coefficient: 12_345, scale: 2)
        )
        #expect(
            Literal.parseDecimal("-0.000000000000000001")
                == .decimal(coefficient: -1, scale: 18)
        )
        #expect(Literal.parseDecimal("1.2.3") == nil)
    }

    @Test("numeric comparison is semantic instead of lexical")
    func exactNumericComparison() {
        #expect(Literal.uint(10).compareExactNumeric(to: .uint(2)) == 1)
        #expect(
            Literal.decimal(coefficient: 100, scale: 2)
                .compareExactNumeric(to: .int(1)) == 0
        )
        #expect(
            Literal.decimal(coefficient: -1, scale: -20)
                .compareExactNumeric(to: .int(Int64.min)) == -1
        )
    }
}
