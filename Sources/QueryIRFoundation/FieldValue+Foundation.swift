import DatabaseTypes
import DatabaseTypesFoundation
import DatabaseValue
import Foundation

extension FieldValue {
    public static func bytes(_ value: Data) -> FieldValue {
        .bytes(ByteString(retaining: value))
    }

    public var dataValue: Data? {
        guard case .bytes(let value) = self else { return nil }
        return Data(copying: value)
    }
}
