import DatabaseValue
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Keeps Foundation data alive while the database value borrows its storage.
struct RetainedDataByteOwner: DatabaseByteOwner {
    let data: Data

    var count: Int {
        data.count
    }

    func borrowBytes(
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) rethrows {
        try data.withUnsafeBytes(body)
    }
}

public extension DatabaseBytes {
    /// Retains Foundation data as immutable database bytes without materializing an array.
    init(retaining data: Data) {
        self.init(retaining: RetainedDataByteOwner(data: data))
    }
}
