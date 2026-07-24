/// Message length encoded by digest algorithms with a 64-bit bit-count field.
struct DigestMessageLength64: Sendable {
    static let maximumByteCount = UInt64.max >> 3

    private(set) var byteCount: UInt64

    init(byteCount: UInt64 = 0) {
        precondition(byteCount <= Self.maximumByteCount)
        self.byteCount = byteCount
    }

    mutating func record(byteCount additionalByteCount: UInt64) -> Bool {
        let (nextByteCount, overflowed) = byteCount.addingReportingOverflow(
            additionalByteCount
        )
        guard !overflowed, nextByteCount <= Self.maximumByteCount else {
            return false
        }
        byteCount = nextByteCount
        return true
    }

    var bitCount: UInt64 {
        byteCount << 3
    }
}

/// Message length encoded by SHA-384 and SHA-512's 128-bit bit-count field.
struct DigestMessageLength128: Sendable {
    static let maximumHighByteCount = UInt64.max >> 3

    private(set) var highByteCount: UInt64
    private(set) var lowByteCount: UInt64

    init(
        highByteCount: UInt64 = 0,
        lowByteCount: UInt64 = 0
    ) {
        precondition(highByteCount <= Self.maximumHighByteCount)
        self.highByteCount = highByteCount
        self.lowByteCount = lowByteCount
    }

    mutating func record(byteCount additionalByteCount: UInt64) -> Bool {
        let (nextLowByteCount, lowOverflowed) = lowByteCount
            .addingReportingOverflow(additionalByteCount)
        let (nextHighByteCount, highOverflowed) = highByteCount
            .addingReportingOverflow(lowOverflowed ? 1 : 0)
        guard
            !highOverflowed,
            nextHighByteCount <= Self.maximumHighByteCount
        else {
            return false
        }
        highByteCount = nextHighByteCount
        lowByteCount = nextLowByteCount
        return true
    }

    var bitCount: (high: UInt64, low: UInt64) {
        (
            high: (highByteCount << 3) | (lowByteCount >> 61),
            low: lowByteCount << 3
        )
    }
}
