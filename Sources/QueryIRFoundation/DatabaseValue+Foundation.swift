import DatabaseValue
import Foundation

extension DatabaseValue {
    public static func bytes(_ value: Data) -> DatabaseValue {
        .bytes(
            DatabaseBytes(
                retaining: RetainedDataByteOwner(data: value)
            )
        )
    }

    public var dataValue: Data? {
        guard case .bytes(let value) = self else { return nil }
        return Data(value)
    }
}
