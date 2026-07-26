import DatabaseTypes

/// Incrementally computes a SHA-1 digest.
///
/// Input buffers are borrowed synchronously. Finalization allocates only the
/// 20-byte digest result and consumes the accumulator.
public struct SHA1Accumulator: Sendable {
    public static let digestByteCount = 20

    private var state = State()
    private var pending: InlineArray<64, UInt8> = .init(repeating: 0)
    private var pendingCount = 0
    private var messageLength = DigestMessageLength64()

    public init() {}

    public mutating func update(_ bytes: ByteString) {
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
            "SHA-1 message exceeds its 64-bit length field"
        )

        var sourceOffset = 0
        if pendingCount > 0 {
            let copiedCount = min(64 - pendingCount, source.count)
            withUnsafeMutableBytes(of: &pending) { destination in
                guard copiedCount > 0 else {
                    return
                }
                let pendingBytes = UnsafeMutableRawBufferPointer(
                    rebasing: destination[
                        pendingCount..<(pendingCount + copiedCount)
                    ]
                )
                let sourceBytes = UnsafeRawBufferPointer(
                    rebasing: source[
                        sourceOffset..<(sourceOffset + copiedCount)
                    ]
                )
                pendingBytes.copyMemory(from: sourceBytes)
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
                rebasing: source[sourceOffset..<(sourceOffset + 64)]
            )
            state = Self.state(afterCompressing: block, from: state)
            sourceOffset += 64
        }

        let remainingCount = source.count - sourceOffset
        guard remainingCount > 0 else {
            return
        }
        withUnsafeMutableBytes(of: &pending) { destination in
            let pendingBytes = UnsafeMutableRawBufferPointer(
                rebasing: destination[0..<remainingCount]
            )
            let sourceBytes = UnsafeRawBufferPointer(
                rebasing: source[sourceOffset..<source.count]
            )
            pendingBytes.copyMemory(from: sourceBytes)
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

    public consuming func finalize() -> ByteString {
        withUnsafeDigestBytes { digestBytes in
            ByteString.copying(count: digestBytes.count) { destination in
                destination.copyMemory(from: digestBytes)
            }
        }
    }

    /// Lends the finalized digest for exactly one synchronous callback.
    ///
    /// The pointer must not escape `body`.
    public consuming func withUnsafeDigestBytes<Result, Failure: Error>(
        _ body: (UnsafeRawBufferPointer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
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
                truncatingIfNeeded: bitCount
                    >> UInt64((7 - offset) * 8)
            )
        }
        processPendingBlock()

        let result: Swift.Result<Result, Failure> = withUnsafeTemporaryAllocation(
            byteCount: Self.digestByteCount,
            alignment: MemoryLayout<UInt32>.alignment
        ) { output in
            Self.writeBigEndian(state.value0, at: 0, to: output)
            Self.writeBigEndian(state.value1, at: 4, to: output)
            Self.writeBigEndian(state.value2, at: 8, to: output)
            Self.writeBigEndian(state.value3, at: 12, to: output)
            Self.writeBigEndian(state.value4, at: 16, to: output)
            do throws(Failure) {
                return .success(try body(UnsafeRawBufferPointer(output)))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    private mutating func processPendingBlock() {
        let currentState = state
        let nextState = withUnsafeBytes(of: &pending) { block in
            Self.state(afterCompressing: block, from: currentState)
        }
        state = nextState
    }

    private static func writeBigEndian(
        _ word: UInt32,
        at offset: Int,
        to output: UnsafeMutableRawBufferPointer
    ) {
        output[offset] = UInt8(truncatingIfNeeded: word >> 24)
        output[offset + 1] = UInt8(truncatingIfNeeded: word >> 16)
        output[offset + 2] = UInt8(truncatingIfNeeded: word >> 8)
        output[offset + 3] = UInt8(truncatingIfNeeded: word)
    }

    private static func state(
        afterCompressing block: UnsafeRawBufferPointer,
        from state: State
    ) -> State {
        precondition(block.count == 64)
        return withUnsafeTemporaryAllocation(
            of: UInt32.self,
            capacity: 80
        ) { schedule in
            for index in 0..<16 {
                let byteOffset = index * 4
                schedule[index] =
                    (UInt32(block[byteOffset]) << 24)
                    | (UInt32(block[byteOffset + 1]) << 16)
                    | (UInt32(block[byteOffset + 2]) << 8)
                    | UInt32(block[byteOffset + 3])
            }
            for index in 16..<80 {
                schedule[index] = (
                    schedule[index - 3]
                        ^ schedule[index - 8]
                        ^ schedule[index - 14]
                        ^ schedule[index - 16]
                ).rotatedLeft(by: 1)
            }

            var a = state.value0
            var b = state.value1
            var c = state.value2
            var d = state.value3
            var e = state.value4

            for index in 0..<80 {
                let mixed: UInt32
                let constant: UInt32
                switch index {
                case 0..<20:
                    mixed = (b & c) | ((~b) & d)
                    constant = 0x5a827999
                case 20..<40:
                    mixed = b ^ c ^ d
                    constant = 0x6ed9eba1
                case 40..<60:
                    mixed = (b & c) | (b & d) | (c & d)
                    constant = 0x8f1bbcdc
                default:
                    mixed = b ^ c ^ d
                    constant = 0xca62c1d6
                }

                let temporary = a.rotatedLeft(by: 5)
                    &+ mixed
                    &+ e
                    &+ constant
                    &+ schedule[index]
                e = d
                d = c
                c = b.rotatedLeft(by: 30)
                b = a
                a = temporary
            }

            return State(
                value0: state.value0 &+ a,
                value1: state.value1 &+ b,
                value2: state.value2 &+ c,
                value3: state.value3 &+ d,
                value4: state.value4 &+ e
            )
        }
    }

    private struct State: Sendable {
        var value0: UInt32 = 0x67452301
        var value1: UInt32 = 0xefcdab89
        var value2: UInt32 = 0x98badcfe
        var value3: UInt32 = 0x10325476
        var value4: UInt32 = 0xc3d2e1f0
    }
}

private extension UInt32 {
    func rotatedLeft(by count: UInt32) -> UInt32 {
        (self << count) | (self >> (32 - count))
    }
}
