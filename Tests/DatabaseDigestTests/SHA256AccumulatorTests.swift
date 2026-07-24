import DatabaseDigest
import DatabaseTypes
import Synchronization
import Testing

@Suite("SHA-256 Accumulator Tests")
struct SHA256AccumulatorTests {
    @Test(
        "Canonical vectors",
        arguments: [
            (0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
            (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
            (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
            (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
            (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
            (1_000, "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"),
        ]
    )
    func canonicalVector(
        byteCount: Int,
        expectedHexadecimal: String
    ) {
        var accumulator = SHA256Accumulator()
        accumulator.update(
            ByteString([UInt8](repeating: 0x61, count: byteCount))
        )

        #expect(hexadecimalString(of: accumulator.finalize()) == expectedHexadecimal)
    }

    @Test func canonicalABCVectorAcrossSegmentedUpdates() {
        var accumulator = SHA256Accumulator()
        accumulator.update(0x61)
        accumulator.update(ByteString([0x62]))
        [UInt8]().withUnsafeBytes { accumulator.update($0) }
        [UInt8](arrayLiteral: 0x63).withUnsafeBytes {
            accumulator.update($0)
        }

        #expect(
            hexadecimalString(of: accumulator.finalize())
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func utf8UpdateUsesCanonicalBytes() {
        var accumulator = SHA256Accumulator()
        accumulator.update(utf8: "データベース")

        #expect(
            hexadecimalString(of: accumulator.finalize())
                == "24be0ba6677a2f0d2f5f46f6ae8d7b2f29916e577885c257822f82199b15bfb7"
        )
    }

    @Test func databaseBytesOwnerIsBorrowedOncePerUpdate() {
        let owner = BorrowCountingByteOwner(
            bytes: [UInt8](repeating: 0x61, count: 1_000)
        )
        var accumulator = SHA256Accumulator()

        accumulator.update(ByteString(retaining: owner))
        let digest = accumulator.finalize()

        #expect(owner.borrowCount == 1)
        #expect(
            hexadecimalString(of: digest)
                == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
        )
    }

    @Test func scopedAndOwnedFinalizationProduceIdenticalBytes() {
        let input = ByteString([UInt8](repeating: 0x5a, count: 257))
        var scopedAccumulator = SHA256Accumulator()
        scopedAccumulator.update(input)
        let scopedDigest = scopedAccumulator.withUnsafeDigestBytes { bytes in
            ByteString.copying(count: bytes.count) { destination in
                destination.copyMemory(from: bytes)
            }
        }

        var ownedAccumulator = SHA256Accumulator()
        ownedAccumulator.update(input)

        #expect(scopedDigest == ownedAccumulator.finalize())
    }

    private func hexadecimalString(of bytes: ByteString) -> String {
        let digits: [UInt8] = Array("0123456789abcdef".utf8)
        return bytes.withUnsafeBytes { source in
            String(decoding: [UInt8](unsafeUninitializedCapacity: source.count * 2) {
                output,
                initializedCount in
                for index in source.indices {
                    output[index * 2] = digits[Int(source[index] >> 4)]
                    output[index * 2 + 1] = digits[Int(source[index] & 0x0f)]
                }
                initializedCount = output.count
            }, as: UTF8.self)
        }
    }
}

private final class BorrowCountingByteOwner: ByteStringOwner {
    let bytes: [UInt8]
    private let borrowCounter = Mutex(0)

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int {
        bytes.count
    }

    var borrowCount: Int {
        borrowCounter.withLock { $0 }
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        borrowCounter.withLock { $0 += 1 }
        try bytes.withUnsafeBytes(body)
    }
}
