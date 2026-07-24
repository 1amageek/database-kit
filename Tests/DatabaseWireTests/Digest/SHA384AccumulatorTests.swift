 import DatabaseWire
import Testing

@Suite("SHA-384 Accumulator Tests")
struct SHA384AccumulatorTests {
    @Test(
        "Canonical and padding-boundary vectors",
        arguments: [
            (0, "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b"),
            (111, "3c37955051cb5c3026f94d551d5b5e2ac38d572ae4e07172085fed81f8466b8f90dc23a8ffcdea0b8d8e58e8fdacc80a"),
            (112, "187d4e07cb306103c69967bf544d0dfbe9042577599c73c330abc0cb64c61236d5ed565ee19119d8c31779a38f791fcd"),
            (127, "9bd06b1763c2cf7aef40e795dc65bc96d59c41b537f3ad72ebdefd485476b5717c1aeb37c327fe9c1831b12b9efd08ae"),
            (128, "edb12730a366098b3b2beac75a3bef1b0969b15c48e2163c23d96994f8d1bef760c7e27f3c464d3829f56c0d53808b0b"),
            (129, "39b6f5a7b0e781dbc419f72e49b30eaac10f2c98c4403bc610da31067fd1b48f324138c8615d2b496d08d73d5e865326"),
            (1_000, "f54480689c6b0b11d0303285d9a81b21a93bca6ba5a1b4472765dca4da45ee328082d469c650cd3b61b16d3266ab8ced"),
        ]
    )
    func canonicalVector(
        byteCount: Int,
        expectedHexadecimal: String
    ) {
        var accumulator = SHA384Accumulator()
        accumulator.update(
            DigestVectorFixture.bytes(repeating: 0x61, count: byteCount)
        )

        #expect(
            DigestVectorFixture.hexadecimalString(of: accumulator.finalize())
                == expectedHexadecimal
        )
    }

    @Test func segmentedABCVector() {
        var accumulator = SHA384Accumulator()
        DigestVectorFixture.forEachSegment(
            of: Array("abc".utf8),
            lengths: [0, 1, 1]
        ) {
            accumulator.update($0)
        }

        #expect(
            accumulator.withUnsafeDigestBytes(
                DigestVectorFixture.hexadecimalString
            ) == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"
        )
    }
}
