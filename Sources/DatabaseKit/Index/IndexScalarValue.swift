import DatabaseTypes

/// A scalar value with a stable index metadata category and a reversible
/// canonical field representation.
public protocol IndexScalarValue:
    FieldValueRepresentable,
    FieldValueDecodable {
    static var indexScalarType: IndexScalarType { get }
}

/// A fixed-width numeric scalar supported by numeric database indexes.
public protocol IndexNumericValue: IndexScalarValue, Numeric, Comparable {}

/// A scalar with a total ordering supported by ordered database indexes.
public protocol IndexComparableValue: IndexScalarValue, Comparable {}

extension Int8: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .int8 }
}

extension Int16: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .int16 }
}

extension Int32: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .int32 }
}

extension Int64: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .int64 }
}

extension UInt8: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .uint8 }
}

extension UInt16: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .uint16 }
}

extension UInt32: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .uint32 }
}

extension UInt64: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .uint64 }
}

extension Float: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .float32 }
}

extension Double: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .float64 }
}

extension String: IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .string }
}

extension CivilDate: IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .date }
}

extension Timestamp: IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .timestamp }
}
