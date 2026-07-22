#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Scalar values that can be reconstructed by a canonical index runtime.
public protocol IndexScalarValue: Codable, Sendable {
    static var indexScalarType: IndexScalarType { get }
}

/// Numeric scalar values supported by numeric aggregation and rank indexes.
public protocol IndexNumericValue: IndexScalarValue, Numeric, Comparable {}

/// Comparable scalar values supported by minimum and maximum indexes.
public protocol IndexComparableValue: IndexScalarValue, Comparable {}

extension Int: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .int }
}

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

extension UInt: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .uint }
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
    public static var indexScalarType: IndexScalarType { .float }
}

extension Double: IndexNumericValue, IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .double }
}

extension String: IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .string }
}

extension Date: IndexComparableValue {
    public static var indexScalarType: IndexScalarType { .date }
}
