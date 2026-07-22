import DatabaseValue
import Foundation

/// Keeps `Data` alive while QueryIR borrows its storage.
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
