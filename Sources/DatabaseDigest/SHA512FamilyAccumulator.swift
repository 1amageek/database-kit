import DatabaseValue

/// Shared streaming state for SHA-384 and SHA-512.
///
/// Both algorithms use the SHA-512 compression function and differ only in
/// their initial state and digest truncation.
struct SHA512FamilyAccumulator: Sendable {
    private var state: State
    private var pending: InlineArray<128, UInt8> = .init(repeating: 0)
    private var pendingCount = 0
    private var messageLength = DigestMessageLength128()

    init(variant: SHA512DigestVariant) {
        state = variant.initialState
    }

    mutating func update(_ bytes: DatabaseBytes) {
        bytes.withUnsafeBytes { source in
            update(source)
        }
    }

    mutating func update(_ byte: UInt8) {
        withUnsafeBytes(of: byte) { source in
            update(source)
        }
    }

    /// Borrows `source` only for the duration of this call.
    mutating func update(_ source: UnsafeRawBufferPointer) {
        precondition(
            messageLength.record(byteCount: UInt64(source.count)),
            "SHA-384/SHA-512 message exceeds its 128-bit length field"
        )

        var sourceOffset = 0
        if pendingCount > 0 {
            let copiedCount = min(128 - pendingCount, source.count)
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
            if pendingCount == 128 {
                processPendingBlock()
                pendingCount = 0
            }
        }

        while source.count - sourceOffset >= 128 {
            let block = UnsafeRawBufferPointer(
                start: source.baseAddress!.advanced(by: sourceOffset),
                count: 128
            )
            state = Self.state(afterCompressing: block, from: state)
            sourceOffset += 128
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

    mutating func update(utf8 value: String) {
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

    consuming func finalize(digestByteCount: Int) -> DatabaseBytes {
        withUnsafeDigestBytes(digestByteCount: digestByteCount) { digestBytes in
            DatabaseBytes.copying(count: digestBytes.count) { destination in
                destination.copyMemory(from: digestBytes)
            }
        }
    }

    /// Lends the finalized digest for exactly one synchronous callback.
    ///
    /// The pointer must not escape `body`.
    consuming func withUnsafeDigestBytes<Result>(
        digestByteCount: Int,
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        precondition(
            digestByteCount == SHA384Accumulator.digestByteCount
                || digestByteCount == SHA512Accumulator.digestByteCount
        )
        let bitCount = messageLength.bitCount

        pending[pendingCount] = 0x80
        pendingCount += 1
        if pendingCount > 112 {
            while pendingCount < 128 {
                pending[pendingCount] = 0
                pendingCount += 1
            }
            processPendingBlock()
            pendingCount = 0
        }
        while pendingCount < 112 {
            pending[pendingCount] = 0
            pendingCount += 1
        }
        Self.writeBigEndian(bitCount.high, at: 112, to: &pending)
        Self.writeBigEndian(bitCount.low, at: 120, to: &pending)
        processPendingBlock()

        return try withUnsafeTemporaryAllocation(
            byteCount: digestByteCount,
            alignment: MemoryLayout<UInt64>.alignment
        ) { output in
            Self.writeBigEndian(state.value0, at: 0, to: output)
            Self.writeBigEndian(state.value1, at: 8, to: output)
            Self.writeBigEndian(state.value2, at: 16, to: output)
            Self.writeBigEndian(state.value3, at: 24, to: output)
            Self.writeBigEndian(state.value4, at: 32, to: output)
            Self.writeBigEndian(state.value5, at: 40, to: output)
            if digestByteCount == SHA512Accumulator.digestByteCount {
                Self.writeBigEndian(state.value6, at: 48, to: output)
                Self.writeBigEndian(state.value7, at: 56, to: output)
            }
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

    private static func writeBigEndian(
        _ word: UInt64,
        at offset: Int,
        to output: UnsafeMutableRawBufferPointer
    ) {
        output[offset] = UInt8(truncatingIfNeeded: word >> 56)
        output[offset + 1] = UInt8(truncatingIfNeeded: word >> 48)
        output[offset + 2] = UInt8(truncatingIfNeeded: word >> 40)
        output[offset + 3] = UInt8(truncatingIfNeeded: word >> 32)
        output[offset + 4] = UInt8(truncatingIfNeeded: word >> 24)
        output[offset + 5] = UInt8(truncatingIfNeeded: word >> 16)
        output[offset + 6] = UInt8(truncatingIfNeeded: word >> 8)
        output[offset + 7] = UInt8(truncatingIfNeeded: word)
    }

    private static func writeBigEndian(
        _ word: UInt64,
        at offset: Int,
        to output: inout InlineArray<128, UInt8>
    ) {
        output[offset] = UInt8(truncatingIfNeeded: word >> 56)
        output[offset + 1] = UInt8(truncatingIfNeeded: word >> 48)
        output[offset + 2] = UInt8(truncatingIfNeeded: word >> 40)
        output[offset + 3] = UInt8(truncatingIfNeeded: word >> 32)
        output[offset + 4] = UInt8(truncatingIfNeeded: word >> 24)
        output[offset + 5] = UInt8(truncatingIfNeeded: word >> 16)
        output[offset + 6] = UInt8(truncatingIfNeeded: word >> 8)
        output[offset + 7] = UInt8(truncatingIfNeeded: word)
    }

    private static func state(
        afterCompressing block: UnsafeRawBufferPointer,
        from state: State
    ) -> State {
        precondition(block.count == 128)
        return withUnsafeTemporaryAllocation(
            of: UInt64.self,
            capacity: 80
        ) { schedule in
            for index in 0..<16 {
                let byteOffset = index * 8
                schedule[index] =
                    (UInt64(block[byteOffset]) << 56)
                    | (UInt64(block[byteOffset + 1]) << 48)
                    | (UInt64(block[byteOffset + 2]) << 40)
                    | (UInt64(block[byteOffset + 3]) << 32)
                    | (UInt64(block[byteOffset + 4]) << 24)
                    | (UInt64(block[byteOffset + 5]) << 16)
                    | (UInt64(block[byteOffset + 6]) << 8)
                    | UInt64(block[byteOffset + 7])
            }
            for index in 16..<80 {
                let value15 = schedule[index - 15]
                let value2 = schedule[index - 2]
                let sigma0 = value15.rotatedRight(by: 1)
                    ^ value15.rotatedRight(by: 8)
                    ^ (value15 >> 7)
                let sigma1 = value2.rotatedRight(by: 19)
                    ^ value2.rotatedRight(by: 61)
                    ^ (value2 >> 6)
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

            for index in 0..<80 {
                let sum1 = e.rotatedRight(by: 14)
                    ^ e.rotatedRight(by: 18)
                    ^ e.rotatedRight(by: 41)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h
                    &+ sum1
                    &+ choice
                    &+ roundConstants[index]
                    &+ schedule[index]
                let sum0 = a.rotatedRight(by: 28)
                    ^ a.rotatedRight(by: 34)
                    ^ a.rotatedRight(by: 39)
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

    struct State: Sendable {
        var value0: UInt64
        var value1: UInt64
        var value2: UInt64
        var value3: UInt64
        var value4: UInt64
        var value5: UInt64
        var value6: UInt64
        var value7: UInt64
    }

    private static let roundConstants: [UInt64] = [
        0x428a2f98d728ae22, 0x7137449123ef65cd,
        0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
        0x3956c25bf348b538, 0x59f111f1b605d019,
        0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
        0xd807aa98a3030242, 0x12835b0145706fbe,
        0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
        0x72be5d74f27b896f, 0x80deb1fe3b1696b1,
        0x9bdc06a725c71235, 0xc19bf174cf692694,
        0xe49b69c19ef14ad2, 0xefbe4786384f25e3,
        0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
        0x2de92c6f592b0275, 0x4a7484aa6ea6e483,
        0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
        0x983e5152ee66dfab, 0xa831c66d2db43210,
        0xb00327c898fb213f, 0xbf597fc7beef0ee4,
        0xc6e00bf33da88fc2, 0xd5a79147930aa725,
        0x06ca6351e003826f, 0x142929670a0e6e70,
        0x27b70a8546d22ffc, 0x2e1b21385c26c926,
        0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
        0x650a73548baf63de, 0x766a0abb3c77b2a8,
        0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001,
        0xc24b8b70d0f89791, 0xc76c51a30654be30,
        0xd192e819d6ef5218, 0xd69906245565a910,
        0xf40e35855771202a, 0x106aa07032bbd1b8,
        0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
        0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
        0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb,
        0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
        0x748f82ee5defb2fc, 0x78a5636f43172f60,
        0x84c87814a1f0ab72, 0x8cc702081a6439ec,
        0x90befffa23631e28, 0xa4506cebde82bde9,
        0xbef9a3f7b2c67915, 0xc67178f2e372532b,
        0xca273eceea26619c, 0xd186b8c721c0c207,
        0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
        0x06f067aa72176fba, 0x0a637dc5a2c898a6,
        0x113f9804bef90dae, 0x1b710b35131c471b,
        0x28db77f523047d84, 0x32caab7b40c72493,
        0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
        0x4cc5d4becb3e42b6, 0x597f299cfc657e2a,
        0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
    ]
}

enum SHA512DigestVariant {
    case sha384
    case sha512

    var initialState: SHA512FamilyAccumulator.State {
        switch self {
        case .sha384:
            return SHA512FamilyAccumulator.State(
                value0: 0xcbbb9d5dc1059ed8,
                value1: 0x629a292a367cd507,
                value2: 0x9159015a3070dd17,
                value3: 0x152fecd8f70e5939,
                value4: 0x67332667ffc00b31,
                value5: 0x8eb44a8768581511,
                value6: 0xdb0c2e0d64f98fa7,
                value7: 0x47b5481dbefa4fa4
            )
        case .sha512:
            return SHA512FamilyAccumulator.State(
                value0: 0x6a09e667f3bcc908,
                value1: 0xbb67ae8584caa73b,
                value2: 0x3c6ef372fe94f82b,
                value3: 0xa54ff53a5f1d36f1,
                value4: 0x510e527fade682d1,
                value5: 0x9b05688c2b3e6c1f,
                value6: 0x1f83d9abfb41bd6b,
                value7: 0x5be0cd19137e2179
            )
        }
    }
}

private extension UInt64 {
    func rotatedRight(by count: UInt64) -> UInt64 {
        (self >> count) | (self << (64 - count))
    }
}
