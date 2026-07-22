import DatabaseValue
@testable import DatabaseWire
import Synchronization
import Testing

@Suite("Database Bytes Ownership Tests")
struct DatabaseBytesOwnershipTests {
    @Test func successPayloadIsAViewIntoTheSingleFinalFrameAllocation() throws {
        let source = DatabaseBytes(
            [UInt8](repeating: 0xa5, count: 1_048_576)
        )

        let encoded = try DatabaseEnvelopeCodec
            .encodeSuccessResponseAndPayload(
                requestID: 42,
                operation: .queryExecute
            ) { writer in
                writer.writeUnframedBytes(source)
            }
        let frameAddress = try #require(
            encoded.frame.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        let payloadAddress = try #require(
            encoded.payload.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )

        #expect(payloadAddress == frameAddress + 22)
        #expect(encoded.payload == source)
        #expect(encoded.frame.count == source.count + 22)
    }

    @Test func exactCopySharesArrayStorageAtArrayOnlyBoundaries() throws {
        let bytes = try DatabaseBytes.copying(count: 4) {
            (output: UnsafeMutableRawBufferPointer) throws(OwnershipTestError) in
            output[0] = 0x10
            output[1] = 0x20
            output[2] = 0x30
            output[3] = 0x40
        }
        let array = bytes.contiguousArray()

        let bytesAddress = try #require(bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })
        let arrayAddress = try #require(array.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })

        #expect(bytesAddress == arrayAddress)
        #expect(array == [0x10, 0x20, 0x30, 0x40])
    }

    @Test func exactCopyPreservesTypedInitializationErrors() {
        #expect(throws: OwnershipTestError.initializationFailed) {
            _ = try DatabaseBytes.copying(count: 4) {
                (_: UnsafeMutableRawBufferPointer) throws(OwnershipTestError) in
                throw .initializationFailed
            }
        }
    }

    @Test func arrayInitializationSharesImmutableStorage() throws {
        var source: [UInt8] = [0x10, 0x20, 0x30, 0x40]
        let sourceAddress = try #require(source.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })

        let bytes = DatabaseBytes(source)
        let bytesAddress = try #require(bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })
        #expect(bytesAddress == sourceAddress)

        source[0] = 0xFF
        #expect(bytes[0] == 0x10)
        #expect(source[0] == 0xFF)
    }

    @Test func slicesBorrowAnOffsetIntoTheSameStorage() throws {
        let bytes: DatabaseBytes = [0x10, 0x20, 0x30, 0x40]
        let slice = bytes.slice(1..<3)
        let sourceAddress = try #require(bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })
        let sliceAddress = try #require(slice.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })

        #expect(sliceAddress == sourceAddress + 1)
        #expect(slice == [0x20, 0x30])
    }

    @Test func externalOwnerIsBorrowedWithoutMaterializing() throws {
        let owner = OwnershipTestByteOwner(
            bytes: [0x10, 0x20, 0x30, 0x40]
        )
        let bytes = DatabaseBytes(retaining: owner)
        let slice = bytes.slice(1..<3)
        var borrowedOwnerAddress: UInt?
        owner.borrowBytes { buffer in
            borrowedOwnerAddress = buffer.baseAddress.map {
                UInt(bitPattern: $0)
            }
        }
        let ownerAddress = try #require(borrowedOwnerAddress)
        let bytesAddress = try #require(bytes.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })
        let sliceAddress = try #require(slice.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })

        #expect(bytesAddress == ownerAddress)
        #expect(sliceAddress == ownerAddress + 1)
        #expect(slice == [0x20, 0x30])
    }

    @Test func viewsFromTheSameOwnerPermitNestedComparisonBorrows() {
        let owner = NestedBorrowDatabaseByteOwner(
            bytes: [0x10, 0x20, 0x30, 0x40]
        )
        let bytes = DatabaseBytes(retaining: owner)
        let lhs = bytes.slice(1..<3)
        let equal = bytes.slice(1..<3)
        let greater = bytes.slice(2..<4)

        #expect(lhs == equal)
        #expect(lhs.lexicographicallyPrecedes(greater))
        #expect(owner.maximumActiveBorrowCount == 2)
    }

    @Test func slicesReleaseOneAllocationExactlyOnce() {
        let releaseProbe = ReleaseProbe()
        var bytes: DatabaseBytes? = makeOwnedBytes(
            [0x10, 0x20, 0x30, 0x40],
            releaseProbe: releaseProbe
        )
        var firstSlice = bytes?.slice(1..<3)
        var secondSlice = bytes?.slice(2..<4)

        bytes = nil
        #expect(releaseProbe.releaseCount == 0)
        #expect(firstSlice?.copyBytes() == [0x20, 0x30])
        #expect(secondSlice?.copyBytes() == [0x30, 0x40])

        firstSlice = nil
        #expect(releaseProbe.releaseCount == 0)
        secondSlice = nil
        #expect(releaseProbe.releaseCount == 1)
    }

    @Test func detachingASliceReleasesItsLargerOwner() throws {
        let releaseProbe = ReleaseProbe()
        var frame: DatabaseBytes? = makeOwnedBytes(
            [0x10, 0x20, 0x30, 0x40, 0x50],
            releaseProbe: releaseProbe
        )
        var token = frame?.slice(2..<4)
        var detached = token?.detached()
        let tokenAddress = try #require(token?.withUnsafeBytes { buffer in
            buffer.baseAddress.map { UInt(bitPattern: $0) }
        })
        let detachedAddress = try #require(
            detached?.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )

        #expect(tokenAddress != detachedAddress)
        frame = nil
        token = nil
        #expect(releaseProbe.releaseCount == 1)
        #expect(detached == [0x30, 0x40])

        detached = nil
        #expect(releaseProbe.releaseCount == 1)
    }

    @Test func detachingFullRangeCreatesExactIndependentStorage() throws {
        let releaseProbe = ReleaseProbe()
        var frame: DatabaseBytes? = makeOwnedBytes(
            [0x10, 0x20, 0x30, 0x40],
            releaseProbe: releaseProbe
        )
        var detached = frame?.detached()
        let frameAddress = try #require(
            frame?.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )
        let detachedAddress = try #require(
            detached?.withUnsafeBytes { buffer in
                buffer.baseAddress.map { UInt(bitPattern: $0) }
            }
        )

        #expect(frameAddress != detachedAddress)
        frame = nil
        #expect(releaseProbe.releaseCount == 1)
        #expect(detached == [0x10, 0x20, 0x30, 0x40])

        detached = nil
        #expect(releaseProbe.releaseCount == 1)
    }

    @Test func detachingEmptySliceReleasesItsLargerOwner() {
        let releaseProbe = ReleaseProbe()
        var frame: DatabaseBytes? = makeOwnedBytes(
            [0x10, 0x20, 0x30, 0x40],
            releaseProbe: releaseProbe
        )
        var emptySlice = frame?.slice(2..<2)
        let detached = emptySlice?.detached()

        frame = nil
        #expect(releaseProbe.releaseCount == 0)
        emptySlice = nil
        #expect(releaseProbe.releaseCount == 1)
        #expect(detached?.isEmpty == true)
    }

    @Test func detachingExactOwnedStorageIsIdempotent() throws {
        let exact = DatabaseBytes.copying(count: 4) { output in
            output.copyBytes(from: [0x10, 0x20, 0x30, 0x40])
        }
        let first = exact.detached()
        let second = first.detached()
        let exactAddress = try #require(exact.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let firstAddress = try #require(first.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let secondAddress = try #require(second.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })

        #expect(exactAddress == firstAddress)
        #expect(firstAddress == secondAddress)
    }

    @Test func encodedFrameIsExactOwnedAndSlicesStillDetach() throws {
        let encoded = try DatabaseWireWriter.encode { writer in
            writer.writeUInt64(0x0102_0304_0506_0708)
        }
        let first = encoded.detached()
        let second = first.detached()
        let encodedAddress = try #require(encoded.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let firstAddress = try #require(first.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let secondAddress = try #require(second.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let slice = encoded.slice(1..<encoded.count)
        let detachedSlice = slice.detached()
        let sliceAddress = try #require(slice.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })
        let detachedSliceAddress = try #require(detachedSlice.withUnsafeBytes {
            $0.baseAddress.map { UInt(bitPattern: $0) }
        })

        #expect(encodedAddress == firstAddress)
        #expect(firstAddress == secondAddress)
        #expect(sliceAddress != detachedSliceAddress)
    }

    private func makeOwnedBytes(
        _ bytes: [UInt8],
        releaseProbe: ReleaseProbe
    ) -> DatabaseBytes {
        let pointer = UnsafeMutableRawPointer.allocate(
            byteCount: bytes.count,
            alignment: MemoryLayout<UInt8>.alignment
        )
        bytes.withUnsafeBytes { source in
            if let sourceAddress = source.baseAddress {
                pointer.copyMemory(
                    from: sourceAddress,
                    byteCount: source.count
                )
            }
        }
        let allocation = DatabaseByteAllocation(
            unsafeAddress: UInt(bitPattern: pointer),
            count: bytes.count,
            deallocator: { address, _ in
                if let pointer = UnsafeMutableRawPointer(bitPattern: address) {
                    pointer.deallocate()
                }
                releaseProbe.recordRelease()
            }
        )
        return DatabaseBytes(allocation: allocation)
    }

    private final class ReleaseProbe: Sendable {
        private let state = Mutex(0)

        var releaseCount: Int {
            state.withLock { $0 }
        }

        func recordRelease() {
            state.withLock { $0 += 1 }
        }
    }
}

private enum OwnershipTestError: Error {
    case initializationFailed
}

private struct OwnershipTestByteOwner: DatabaseByteOwner {
    let bytes: [UInt8]

    var count: Int {
        bytes.count
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        try bytes.withUnsafeBytes(body)
    }
}

private final class NestedBorrowDatabaseByteOwner: DatabaseByteOwner {
    let bytes: [UInt8]
    private let state = Mutex((active: 0, maximum: 0))

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var count: Int {
        bytes.count
    }

    var maximumActiveBorrowCount: Int {
        state.withLock { $0.maximum }
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        state.withLock { state in
            state.active += 1
            state.maximum = Swift.max(state.maximum, state.active)
        }
        defer {
            state.withLock { $0.active -= 1 }
        }
        try bytes.withUnsafeBytes(body)
    }
}
