import DatabaseKit
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

extension Date: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .timestamp }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        do {
            return .timestamp(try Timestamp(self))
        } catch let error {
            throw .invalidScalar(
                type: "Date",
                reason: String(describing: error)
            )
        }
    }
}

extension Date: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Date {
        guard case .timestamp(let timestamp) = value else {
            throw .invalidValue(
                field: field,
                expected: "a timestamp"
            )
        }
        return Date(timestamp)
    }
}
