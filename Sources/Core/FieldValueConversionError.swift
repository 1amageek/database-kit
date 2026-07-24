import DatabaseTypes
import DatabaseTypesFoundation

public enum FieldValueConversionError: Error, Sendable, Equatable {
    case timestamp(TimestampConversionError)
}
