@testable import DatabaseWire
import Testing

@Suite("SHA-512 Accumulator Tests")
struct SHA512AccumulatorTests {
    @Test(
        "Canonical and padding-boundary vectors",
        arguments: [
            (0, "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"),
            (111, "fa9121c7b32b9e01733d034cfc78cbf67f926c7ed83e82200ef86818196921760b4beff48404df811b953828274461673c68d04e297b0eb7b2b4d60fc6b566a2"),
            (112, "c01d080efd492776a1c43bd23dd99d0a2e626d481e16782e75d54c2503b5dc32bd05f0f1ba33e568b88fd2d970929b719ecbb152f58f130a407c8830604b70ca"),
            (127, "828613968b501dc00a97e08c73b118aa8876c26b8aac93df128502ab360f91bab50a51e088769a5c1eff4782ace147dce3642554199876374291f5d921629502"),
            (128, "b73d1929aa615934e61a871596b3f3b33359f42b8175602e89f7e06e5f658a243667807ed300314b95cacdd579f3e33abdfbe351909519a846d465c59582f321"),
            (129, "4f681e0bd53cda4b5a2041cc8a06f2eabde44fb16c951fbd5b87702f07aeab611565b19c47fde30587177ebb852e3971bbd8d3fd30da18d71037dfbd98420429"),
            (1_000, "67ba5535a46e3f86dbfbed8cbbaf0125c76ed549ff8b0b9e03e0c88cf90fa634fa7b12b47d77b694de488ace8d9a65967dc96df599727d3292a8d9d447709c97"),
        ]
    )
    func canonicalVector(
        byteCount: Int,
        expectedHexadecimal: String
    ) {
        var accumulator = SHA512Accumulator()
        accumulator.update(
            DigestVectorFixture.bytes(repeating: 0x61, count: byteCount)
        )

        #expect(
            DigestVectorFixture.hexadecimalString(of: accumulator.finalize())
                == expectedHexadecimal
        )
    }

    @Test func segmentedABCVector() {
        var accumulator = SHA512Accumulator()
        DigestVectorFixture.forEachSegment(
            of: Array("abc".utf8),
            lengths: [0, 1, 1]
        ) {
            accumulator.update($0)
        }

        #expect(
            accumulator.withUnsafeDigestBytes(
                DigestVectorFixture.hexadecimalString
            ) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
        )
    }
}
