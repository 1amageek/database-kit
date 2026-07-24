@testable import DatabaseWire
import Testing

@Suite("Digest Message Length Tests")
struct DigestMessageLengthTests {
    @Test func sixtyFourBitLengthAcceptsItsBoundary() {
        var length = DigestMessageLength64(
            byteCount: DigestMessageLength64.maximumByteCount - 1
        )

        let acceptedBoundaryByte = length.record(byteCount: 1)
        #expect(acceptedBoundaryByte)
        #expect(
            length.bitCount == UInt64.max &- 7
        )
        let acceptedOverflowingByte = length.record(byteCount: 1)
        #expect(!acceptedOverflowingByte)
        #expect(
            length.byteCount == DigestMessageLength64.maximumByteCount
        )
    }

    @Test func oneHundredTwentyEightBitLengthCarriesIntoHighWord() {
        var length = DigestMessageLength128(
            highByteCount: DigestMessageLength128.maximumHighByteCount - 1,
            lowByteCount: UInt64.max
        )

        let acceptedCarryByte = length.record(byteCount: 1)
        #expect(acceptedCarryByte)
        #expect(
            length.highByteCount
                == DigestMessageLength128.maximumHighByteCount
        )
        #expect(length.lowByteCount == 0)
        #expect(
            length.bitCount
                == (
                    high: UInt64.max &- 7,
                    low: 0
                )
        )
    }

    @Test func oneHundredTwentyEightBitLengthRejectsOverflow() {
        var length = DigestMessageLength128(
            highByteCount: DigestMessageLength128.maximumHighByteCount,
            lowByteCount: UInt64.max
        )

        let acceptedOverflowingByte = length.record(byteCount: 1)
        #expect(!acceptedOverflowingByte)
        #expect(
            length.highByteCount
                == DigestMessageLength128.maximumHighByteCount
        )
        #expect(length.lowByteCount == UInt64.max)
    }
}
