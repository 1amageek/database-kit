import DatabaseKit
import DatabaseTypes
import DatabaseTypesFoundation
import Foundation

extension Decimal: FieldValueEncodable {
    public static var fieldSchemaType: FieldSchemaType { .decimal }

    public func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        do {
            return .decimal(try ExactDecimal(self))
        } catch let error {
            throw .invalidScalar(
                type: "Decimal",
                reason: String(describing: error)
            )
        }
    }
}

extension Decimal: FieldValueDecodable {
    public static func decodeFieldValue(
        _ value: FieldValue,
        field: String
    ) throws(PersistableDecodingError) -> Decimal {
        guard case .decimal(let decimal) = value else {
            throw .invalidValue(
                field: field,
                expected: "an exact decimal"
            )
        }
        do {
            return try Decimal(decimal)
        } catch {
            throw .invalidValue(
                field: field,
                expected: "a Foundation Decimal in range"
            )
        }
    }
}
