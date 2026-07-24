import DatabaseTypes
import Synchronization

final class DigestBorrowCountingOwner: ByteStringOwner {
    let bytes: [UInt8]
    private let counter = Mutex(0)

    init(byte: UInt8, count: Int) {
        bytes = [UInt8](repeating: byte, count: count)
    }

    var count: Int {
        bytes.count
    }

    var borrowCount: Int {
        counter.withLock { $0 }
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        counter.withLock { $0 += 1 }
        try bytes.withUnsafeBytes(body)
    }
}
