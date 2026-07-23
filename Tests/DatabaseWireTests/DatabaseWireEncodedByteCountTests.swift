import DatabaseValue
import Synchronization
import Testing
@testable import DatabaseWire

@Suite("DatabaseWire encoded byte count")
struct DatabaseWireEncodedByteCountTests {
    @Test("byte count matches the canonical exact encoding")
    func byteCountMatchesCanonicalEncoding() throws {
        var invocationCount = 0

        let byteCount = try DatabaseWireWriter.encodedByteCount {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) -> Void in
            invocationCount += 1
            writer.writeUInt64(0x0102_0304_0506_0708)
            try writer.writeString("calendar")
        }
        let encoded = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) -> Void in
            writer.writeUInt64(0x0102_0304_0506_0708)
            try writer.writeString("calendar")
        }

        #expect(byteCount == encoded.count)
        #expect(invocationCount == 1)
    }

    @Test("frame limit rejects the complete canonical byte count")
    func frameLimitRejectsCanonicalByteCount() throws {
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: 7,
            maximumStringBytes: 32,
            maximumByteStringBytes: 32,
            maximumCollectionCount: 8,
            maximumNestingDepth: 8,
            maximumObjectCount: 8
        )
        var invocationCount = 0

        #expect(
            throws: DatabaseWireError.frameTooLarge(
                actual: 8,
                maximum: 7
            )
        ) {
            _ = try DatabaseWireWriter.encodedByteCount(
                limits: limits
            ) { writer in
                invocationCount += 1
                writer.writeUInt64(0)
            }
        }
        #expect(invocationCount == 1)
    }

    @Test("string and object limits remain authoritative")
    func valueLimitsRemainAuthoritative() throws {
        let stringLimits = try DatabaseWireLimits(
            maximumFrameBytes: 32,
            maximumStringBytes: 1,
            maximumByteStringBytes: 32,
            maximumCollectionCount: 8,
            maximumNestingDepth: 8,
            maximumObjectCount: 8
        )
        #expect(
            throws: DatabaseWireError.stringTooLarge(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try DatabaseWireWriter.encodedByteCount(
                limits: stringLimits
            ) {
                (writer: inout DatabaseWireWriter)
                    throws(DatabaseWireError) -> Void in
                try writer.writeString("é")
            }
        }

        let objectLimits = try DatabaseWireLimits(
            maximumFrameBytes: 32,
            maximumStringBytes: 32,
            maximumByteStringBytes: 32,
            maximumCollectionCount: 8,
            maximumNestingDepth: 8,
            maximumObjectCount: 1
        )
        #expect(
            throws: DatabaseWireError.objectBudgetExceeded(
                actual: 2,
                maximum: 1
            )
        ) {
            _ = try DatabaseWireWriter.encodedByteCount(
                limits: objectLimits
            ) {
                (writer: inout DatabaseWireWriter)
                    throws(DatabaseWireError) -> Void in
                try writer.registerObjects(2)
            }
        }
    }

    @Test("logical payloads are counted without output allocation or source borrow")
    func logicalPayloadDoesNotRequireStorage() throws {
        let logicalByteCount = 1_073_741_824
        let encodedByteCount = logicalByteCount + 4
        let source = BorrowObservedByteOwner(count: logicalByteCount)
        let payload = DatabaseBytes(retaining: source)
        let limits = try DatabaseWireLimits(
            maximumFrameBytes: encodedByteCount,
            maximumStringBytes: 32,
            maximumByteStringBytes: logicalByteCount,
            maximumCollectionCount: 8,
            maximumNestingDepth: 8,
            maximumObjectCount: 8
        )

        let byteCount = try DatabaseWireWriter.encodedByteCount(
            limits: limits
        ) {
            (writer: inout DatabaseWireWriter)
                throws(DatabaseWireError) -> Void in
            try writer.writeBytes(payload)
        }

        #expect(byteCount == encodedByteCount)
        #expect(source.borrowCount == 0)
    }

    @Test("deferred byte count overflow is reported without source borrow")
    func deferredOverflowIsReported() {
        let source = BorrowObservedByteOwner(count: Int.max)
        let payload = DatabaseBytes(retaining: source)

        #expect(throws: DatabaseWireError.byteCountOverflow) {
            _ = try DatabaseWireWriter.encodedByteCount(
                limits: .default
            ) { writer in
                writer.writeUnframedBytes(payload)
                writer.writeUInt8(0)
            }
        }
        #expect(source.borrowCount == 0)
    }
}

private final class BorrowObservedByteOwner: DatabaseByteOwner {
    let count: Int
    private let borrowCountState = Mutex(0)

    init(count: Int) {
        self.count = count
    }

    var borrowCount: Int {
        borrowCountState.withLock { $0 }
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        borrowCountState.withLock { $0 += 1 }
        try body(UnsafeRawBufferPointer(start: nil, count: 0))
    }
}
