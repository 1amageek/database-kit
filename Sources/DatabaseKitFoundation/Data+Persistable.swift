import DatabaseKit
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

extension Data: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .bytes }

    public func encodeFieldValue() -> FieldValue {
        .bytes(ByteString(retaining: self))
    }
}

extension Data: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Data {
        guard case .bytes(let bytes) = value else {
            throw .invalidValue(
                field: field,
                expected: "bytes"
            )
        }

        // Data cannot retain an arbitrary ByteString owner through its public
        // value-semantic API, so the native output boundary requires one copy.
        return Data(copying: bytes)
    }
}
