public import DatabaseTypes

/// Incrementally computes a canonical SHA-256 digest.
///
/// Input buffers are borrowed synchronously. Finalization allocates only the
/// 32-byte digest result and consumes the accumulator.
public struct SHA256Accumulator: Sendable {
    public static let digestByteCount = 32

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
            "SHA-256 message exceeds its 64-bit length field"
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
            withUnsafeBytes(of: byte) { source in
                update(source)
            }
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
                truncatingIfNeeded: bitCount >> UInt64((7 - offset) * 8)
            )
        }
        processPendingBlock()

        return try withUnsafeTemporaryAllocation(
            byteCount: Self.digestByteCount,
            alignment: MemoryLayout<UInt32>.alignment
        ) { output in
            Self.write(state.value0, at: 0, to: output)
            Self.write(state.value1, at: 4, to: output)
            Self.write(state.value2, at: 8, to: output)
            Self.write(state.value3, at: 12, to: output)
            Self.write(state.value4, at: 16, to: output)
            Self.write(state.value5, at: 20, to: output)
            Self.write(state.value6, at: 24, to: output)
            Self.write(state.value7, at: 28, to: output)
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

    private static func write(
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
            capacity: 64
        ) { schedule in
            for index in 0..<16 {
                let byteOffset = index * 4
                schedule[index] =
                    (UInt32(block[byteOffset]) << 24)
                    | (UInt32(block[byteOffset + 1]) << 16)
                    | (UInt32(block[byteOffset + 2]) << 8)
                    | UInt32(block[byteOffset + 3])
            }
            for index in 16..<64 {
                let value15 = schedule[index - 15]
                let value2 = schedule[index - 2]
                let sigma0 = value15.rotatedRight(by: 7)
                    ^ value15.rotatedRight(by: 18)
                    ^ (value15 >> 3)
                let sigma1 = value2.rotatedRight(by: 17)
                    ^ value2.rotatedRight(by: 19)
                    ^ (value2 >> 10)
                schedule[index] = schedule[index - 16]
                    &+ sigma0
                    &+ schedule[index - 7]
                    &+ sigma1
            }

            var a = state.value0
            var b = state.value1
            var c = state.value2
            var d = state.value3
            var e = state.value4
            var f = state.value5
            var g = state.value6
            var h = state.value7
            for index in 0..<64 {
                let sum1 = e.rotatedRight(by: 6)
                    ^ e.rotatedRight(by: 11)
                    ^ e.rotatedRight(by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h
                    &+ sum1
                    &+ choice
                    &+ roundConstants[index]
                    &+ schedule[index]
                let sum0 = a.rotatedRight(by: 2)
                    ^ a.rotatedRight(by: 13)
                    ^ a.rotatedRight(by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority

                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }

            return State(
                value0: state.value0 &+ a,
                value1: state.value1 &+ b,
                value2: state.value2 &+ c,
                value3: state.value3 &+ d,
                value4: state.value4 &+ e,
                value5: state.value5 &+ f,
                value6: state.value6 &+ g,
                value7: state.value7 &+ h
            )
        }
    }

    private struct State: Sendable {
        var value0: UInt32 = 0x6a09e667
        var value1: UInt32 = 0xbb67ae85
        var value2: UInt32 = 0x3c6ef372
        var value3: UInt32 = 0xa54ff53a
        var value4: UInt32 = 0x510e527f
        var value5: UInt32 = 0x9b05688c
        var value6: UInt32 = 0x1f83d9ab
        var value7: UInt32 = 0x5be0cd19
    }

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}

private extension UInt32 {
    func rotatedRight(by count: UInt32) -> UInt32 {
        (self >> count) | (self << (32 - count))
    }
}
