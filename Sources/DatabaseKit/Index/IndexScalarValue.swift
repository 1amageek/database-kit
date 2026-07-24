import DatabaseTypes

/// Scalar values that can be reconstructed by a canonical index runtime.
public protocol IndexScalarValue: Sendable {
    static var indexScalarType: IndexScalarType { get }
}

/// Numeric scalar values supported by numeric aggregation and rank indexes.
public protocol IndexNumericValue: IndexScalarValue, Numeric, Comparable {}

/// Comparable scalar values supported by minimum and maximum indexes.
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
