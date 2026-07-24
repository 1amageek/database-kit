#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseTypes
import DatabaseTypesFoundation
import DatabaseValue

extension Data: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .bytes(ByteString(retaining: self))
    }
}

extension Foundation.UUID: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .uuid(DatabaseTypes.UUID(self))
    }
}

extension Date: FieldValueConvertible {
    public func toFieldValue() throws(FieldValueConversionError) -> FieldValue {
        do {
            return .timestamp(try Timestamp(self))
        } catch let error {
            throw .timestamp(error)
        }
    }
}
