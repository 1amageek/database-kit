public import DatabaseValue

/// Incrementally computes an MD5 digest.
///
/// Input buffers are borrowed synchronously. Finalization allocates only the
/// 16-byte digest result and consumes the accumulator.
public struct MD5Accumulator: Sendable {
    public static let digestByteCount = 16

    private var state = State()
    private var pending: InlineArray<64, UInt8> = .init(repeating: 0)
    private var pendingCount = 0
    private var messageLength = DigestMessageLength64()

    public init() {}

    public mutating func update(_ bytes: DatabaseBytes) {
        bytes.withUnsafeBytes { source in
            update(source)
        }
    }

    public mutating func update(_ byte: UInt8) {
        withUnsafeBytes(of: byte) { source in
            update(source)
        }
    }

    /// Borrows `source` only for the duration of this call.
    public mutating func update(_ source: UnsafeRawBufferPointer) {
        precondition(
            messageLength.record(byteCount: UInt64(source.count)),
            "MD5 message exceeds its 64-bit length field"
        )

        var sourceOffset = 0
        if pendingCount > 0 {
            let copiedCount = min(64 - pendingCount, source.count)
            withUnsafeMutableBytes(of: &pending) { destination in
                guard copiedCount > 0 else {
                    return
                }
                destination.baseAddress!
                    .advanced(by: pendingCount)
                    .copyMemory(
                        from: source.baseAddress!.advanced(by: sourceOffset),
                        byteCount: copiedCount
                    )
            }
            pendingCount += copiedCount
            sourceOffset += copiedCount
            if pendingCount == 64 {
                processPendingBlock()
                pendingCount = 0
            }
        }

        while source.count - sourceOffset >= 64 {
            let block = UnsafeRawBufferPointer(
                start: source.baseAddress!.advanced(by: sourceOffset),
                count: 64
            )
            state = Self.state(afterCompressing: block, from: state)
            sourceOffset += 64
        }

        let remainingCount = source.count - sourceOffset
        guard remainingCount > 0 else {
            return
        }
        withUnsafeMutableBytes(of: &pending) { destination in
            destination.baseAddress!.copyMemory(
                from: source.baseAddress!.advanced(by: sourceOffset),
                byteCount: remainingCount
            )
        }
        pendingCount = remainingCount
    }

    public mutating func update(utf8 value: String) {
        let usedContiguousStorage = value.utf8.withContiguousStorageIfAvailable {
            bytes -> Bool in
            update(UnsafeRawBufferPointer(bytes))
            return true
        } ?? false
        guard !usedContiguousStorage else {
            return
        }
        for byte in value.utf8 {
            update(byte)
        }
    }

    public consuming func finalize() -> DatabaseBytes {
        withUnsafeDigestBytes { digestBytes in
            DatabaseBytes.copying(count: digestBytes.count) { destination in
                destination.copyMemory(from: digestBytes)
            }
        }
    }

    /// Lends the finalized digest for exactly one synchronous callback.
    ///
    /// The pointer must not escape `body`.
    public consuming func withUnsafeDigestBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        let bitCount = messageLength.bitCount

        pending[pendingCount] = 0x80
        pendingCount += 1
        if pendingCount > 56 {
            while pendingCount < 64 {
                pending[pendingCount] = 0
                pendingCount += 1
            }
            processPendingBlock()
            pendingCount = 0
        }
        while pendingCount < 56 {
            pending[pendingCount] = 0
            pendingCount += 1
        }
        for offset in 0..<8 {
            pending[56 + offset] = UInt8(
                truncatingIfNeeded: bitCount >> UInt64(offset * 8)
            )
        }
        processPendingBlock()

        return try withUnsafeTemporaryAllocation(
            byteCount: Self.digestByteCount,
            alignment: MemoryLayout<UInt32>.alignment
        ) { output in
            Self.writeLittleEndian(state.value0, at: 0, to: output)
            Self.writeLittleEndian(state.value1, at: 4, to: output)
            Self.writeLittleEndian(state.value2, at: 8, to: output)
            Self.writeLittleEndian(state.value3, at: 12, to: output)
            return try body(UnsafeRawBufferPointer(output))
        }
    }

    private mutating func processPendingBlock() {
        let currentState = state
        let nextState = withUnsafeBytes(of: &pending) { block in
            Self.state(afterCompressing: block, from: currentState)
        }
        state = nextState
    }

    private static func writeLittleEndian(
        _ word: UInt32,
        at offset: Int,
        to output: UnsafeMutableRawBufferPointer
    ) {
        output[offset] = UInt8(truncatingIfNeeded: word)
        output[offset + 1] = UInt8(truncatingIfNeeded: word >> 8)
        output[offset + 2] = UInt8(truncatingIfNeeded: word >> 16)
        output[offset + 3] = UInt8(truncatingIfNeeded: word >> 24)
    }

    private static func state(
        afterCompressing block: UnsafeRawBufferPointer,
        from state: State
    ) -> State {
        precondition(block.count == 64)
        return withUnsafeTemporaryAllocation(
            of: UInt32.self,
            capacity: 16
        ) { words in
            for index in 0..<16 {
                let byteOffset = index * 4
                words[index] =
                    UInt32(block[byteOffset])
                    | (UInt32(block[byteOffset + 1]) << 8)
                    | (UInt32(block[byteOffset + 2]) << 16)
                    | (UInt32(block[byteOffset + 3]) << 24)
            }

            var a = state.value0
            var b = state.value1
            var c = state.value2
            var d = state.value3

            for index in 0..<64 {
                let mixed: UInt32
                let wordIndex: Int
                switch index {
                case 0..<16:
                    mixed = (b & c) | ((~b) & d)
                    wordIndex = index
                case 16..<32:
                    mixed = (d & b) | ((~d) & c)
                    wordIndex = (5 * index + 1) & 15
                case 32..<48:
                    mixed = b ^ c ^ d
                    wordIndex = (3 * index + 5) & 15
                default:
                    mixed = c ^ (b | (~d))
                    wordIndex = (7 * index) & 15
                }

                let nextB = b &+ (
                    a
                        &+ mixed
                        &+ roundConstants[index]
                        &+ words[wordIndex]
                ).rotatedLeft(by: rotationCounts[index])
                a = d
                d = c
                c = b
                b = nextB
            }

            return State(
                value0: state.value0 &+ a,
                value1: state.value1 &+ b,
                value2: state.value2 &+ c,
                value3: state.value3 &+ d
            )
        }
    }

    private struct State: Sendable {
        var value0: UInt32 = 0x67452301
        var value1: UInt32 = 0xefcdab89
        var value2: UInt32 = 0x98badcfe
        var value3: UInt32 = 0x10325476
    }

    private static let rotationCounts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    ]

    private static let roundConstants: [UInt32] = [
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
        0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
        0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
        0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
        0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
        0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
        0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
        0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
        0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    ]
}

private extension UInt32 {
    func rotatedLeft(by count: UInt32) -> UInt32 {
        (self << count) | (self >> (32 - count))
    }
}
