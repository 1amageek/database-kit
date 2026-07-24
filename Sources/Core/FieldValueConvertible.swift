import DatabaseTypes
import DatabaseValue

/// A value that can be represented by the canonical database field model.
public protocol FieldValueConvertible: Sendable {
    func toFieldValue() throws(FieldValueConversionError) -> FieldValue
}

extension Bool: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .bool(self) }
}

extension Int: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int8(self) }
}

extension Int16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int16(self) }
}

extension Int32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int32(self) }
}

extension Int64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(self) }
}

extension UInt: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint8(self) }
}

extension UInt16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint16(self) }
}

extension UInt32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint32(self) }
}

extension UInt64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(self) }
}

extension Float: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .float32(self) }
}

extension Double: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .float64(self) }
}

extension String: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .string(self) }
}

extension ExactDecimal: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .decimal(self) }
}

extension ByteString: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .bytes(self) }
}

extension CivilDate: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .date(self) }
}

extension CivilTime: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .time(self) }
}

extension CivilDateTime: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .dateTime(self) }
}

extension Timestamp: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .timestamp(self) }
}

extension TimeSpan: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .timeSpan(self) }
}

extension CalendarPeriod: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .calendarPeriod(self) }
}

extension GeographicPoint: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .geographicPoint(self) }
}

extension GeographicPosition: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .geographicPosition(self) }
}

extension DatabaseTypes.Vector: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .vector(self) }
}

extension DatabaseTypes.UUID: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uuid(self) }
}

extension FieldObject: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .object(self) }
}

extension EntityReference: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .reference(self) }
}

extension RDFTerm: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .rdfTerm(self) }
}

extension Array: FieldValueConvertible where Element: FieldValueConvertible {
    public func toFieldValue() throws(FieldValueConversionError) -> FieldValue {
        var values: [FieldValue] = []
        values.reserveCapacity(count)
        for element in self {
            values.append(try element.toFieldValue())
        }
        return .array(values)
    }
}

extension Optional: FieldValueConvertible where Wrapped: FieldValueConvertible {
    public func toFieldValue() throws(FieldValueConversionError) -> FieldValue {
        switch self {
        case .some(let value):
            return try value.toFieldValue()
        case .none:
            return .null
        }
    }
}

extension FieldValue: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { self }
}
