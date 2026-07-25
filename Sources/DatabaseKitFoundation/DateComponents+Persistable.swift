import DatabaseKit
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

extension DateComponents: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .calendarPeriod }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        do {
            return .calendarPeriod(try CalendarPeriod(self))
        } catch let error {
            throw .invalidScalar(
                type: "DateComponents",
                reason: String(describing: error)
            )
        }
    }
}

extension DateComponents: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> DateComponents {
        guard case .calendarPeriod(let period) = value else {
            throw .invalidValue(
                field: field,
                expected: "a calendar period"
            )
        }
        do {
            return try DateComponents(period)
        } catch {
            throw .invalidValue(
                field: field,
                expected: "Foundation date components in range"
            )
        }
    }
}
