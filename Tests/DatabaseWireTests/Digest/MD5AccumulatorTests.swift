 import DatabaseWire
import Testing

@Suite("MD5 Accumulator Tests")
struct MD5AccumulatorTests {
    @Test(
        "Canonical and padding-boundary vectors",
        arguments: [
            (0, "d41d8cd98f00b204e9800998ecf8427e"),
            (55, "ef1772b6dff9a122358552954ad0df65"),
            (56, "3b0c8ac703f828b04c6c197006d17218"),
            (63, "b06521f39153d618550606be297466d5"),
            (64, "014842d480b571495a4a0363793f7367"),
            (65, "c743a45e0d2e6a95cb859adae0248435"),
            (1_000, "cabe45dcc9ae5b66ba86600cca6b8ba8"),
        ]
    )
    func canonicalVector(
        byteCount: Int,
        expectedHexadecimal: String
    ) {
        var accumulator = MD5Accumulator()
        accumulator.update(
            DigestVectorFixture.bytes(repeating: 0x61, count: byteCount)
        )

        #expect(
            DigestVectorFixture.hexadecimalString(of: accumulator.finalize())
                == expectedHexadecimal
        )
    }

    @Test func segmentedABCVector() {
        var accumulator = MD5Accumulator()
        DigestVectorFixture.forEachSegment(
            of: Array("abc".utf8),
            lengths: [0, 1, 1]
        ) {
            accumulator.update($0)
        }

        #expect(
            accumulator.withUnsafeDigestBytes(
                DigestVectorFixture.hexadecimalString
            ) == "900150983cd24fb0d6963f7d28e17f72"
        )
    }
}
