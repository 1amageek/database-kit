 import DatabaseWire
import Testing

@Suite("SHA-1 Accumulator Tests")
struct SHA1AccumulatorTests {
    @Test(
        "Canonical and padding-boundary vectors",
        arguments: [
            (0, "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
            (55, "c1c8bbdc22796e28c0e15163d20899b65621d65a"),
            (56, "c2db330f6083854c99d4b5bfb6e8f29f201be699"),
            (63, "03f09f5b158a7a8cdad920bddc29b81c18a551f5"),
            (64, "0098ba824b5c16427bd7a1122a5a442a25ec644d"),
            (65, "11655326c708d70319be2610e8a57d9a5b959d3b"),
            (1_000, "291e9a6c66994949b57ba5e650361e98fc36b1ba"),
        ]
    )
    func canonicalVector(
        byteCount: Int,
        expectedHexadecimal: String
    ) {
        var accumulator = SHA1Accumulator()
        accumulator.update(
            DigestVectorFixture.bytes(repeating: 0x61, count: byteCount)
        )

        #expect(
            DigestVectorFixture.hexadecimalString(of: accumulator.finalize())
                == expectedHexadecimal
        )
    }

    @Test func segmentedABCVector() {
        var accumulator = SHA1Accumulator()
        DigestVectorFixture.forEachSegment(
            of: Array("abc".utf8),
            lengths: [0, 1, 1]
        ) {
            accumulator.update($0)
        }

        #expect(
            accumulator.withUnsafeDigestBytes(
                DigestVectorFixture.hexadecimalString
            ) == "a9993e364706816aba3e25717850c26c9cd0d89d"
        )
    }
}
