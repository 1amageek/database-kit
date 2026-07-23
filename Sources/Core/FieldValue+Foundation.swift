#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseValue

extension Data: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .bytes(DatabaseBytes(retaining: RetainedDataByteOwner(data: self)))
    }
}

extension UUID: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        guard let value = DatabaseUUID(
            canonicalString: uuidString.lowercased()
        ) else {
            preconditionFailure("Foundation UUID did not produce a canonical UUID")
        }
        return .uuid(value)
    }
}

extension Date: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        let interval = timeIntervalSince1970
        let seconds = interval.rounded(.down)
        let fractional = interval - seconds
        return .timestamp(
            DatabaseTimestamp(
                secondsSinceUnixEpoch: Int64(seconds),
                nanoseconds: UInt32((fractional * 1_000_000_000).rounded())
            )
        )
    }
}
