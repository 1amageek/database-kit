#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DatabaseValue
import DatabaseValueCodable

#if canImport(ObjectiveC)
import class Foundation.NSNull
#endif

/// Represents a field value that can be compared and hashed
///
/// Used for query conditions, statistics (HyperLogLog), and field comparisons.
/// Similar to fdb-record-layer's ComparableValue.
///
/// **Supported Types**:
/// - `int64`: 64-bit signed integer
/// - `uint64`: 64-bit unsigned integer
/// - `double`: 64-bit floating point
/// - `string`: UTF-8 string
/// - `bool`: Boolean value
/// - `data`: Binary data
/// - `null`: Null/missing value
///
/// **Usage**:
/// ```swift
/// let value = FieldValue.string("hello")
/// let number = FieldValue.int64(42)
///
/// // Comparison
/// if value < FieldValue.string("world") {
///     print("'hello' comes before 'world'")
/// }
///
/// // For HyperLogLog
/// var hll = HyperLogLog()
/// hll.add(value)
/// ```
public enum FieldValue: Sendable, Codable {
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case string(String)
    case bool(Bool)
    case data(DatabaseBytes)
    case rdfTerm(DatabaseRDFTerm)
    case null
    case array([FieldValue])

    // MARK: - Convenience Initializers

    /// Create from any supported type
    ///
    /// Returns nil if the value type is not supported.
    public init?(_ value: Any) {
        switch value {
        case let v as Int64:
            self = .int64(v)
        case let v as Int:
            self = .int64(Int64(v))
        case let v as Int32:
            self = .int64(Int64(v))
        case let v as Int16:
            self = .int64(Int64(v))
        case let v as Int8:
            self = .int64(Int64(v))
        case let v as UInt64:
            self = .uint64(v)
        case let v as UInt:
            self = .uint64(UInt64(v))
        case let v as UInt32:
            self = .uint64(UInt64(v))
        case let v as UInt16:
            self = .uint64(UInt64(v))
        case let v as UInt8:
            self = .uint64(UInt64(v))
        case let v as Double:
            self = .double(v)
        case let v as Float:
            self = .double(Double(v))
        case let v as String:
            self = .string(v)
        case let v as Bool:
            self = .bool(v)
        case let v as DatabaseBytes:
            self = .data(v)
        case let v as Data:
            self = .data(
                DatabaseBytes(retaining: RetainedDataByteOwner(data: v))
            )
        case let v as [UInt8]:
            self = .data(DatabaseBytes(v))
        case let v as Date:
            self = .double(v.timeIntervalSince1970)
        case let v as DatabaseRDFTerm:
            self = .rdfTerm(v)
        #if canImport(ObjectiveC)
        case is NSNull:
            self = .null
        #endif
        case nil as Any?:
            self = .null
        default:
            return nil
        }
    }

    // MARK: - Type Checks

    /// Returns true if this is a null value
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Returns true if this is a numeric value.
    public var isNumeric: Bool {
        switch self {
        case .int64, .uint64, .double:
            return true
        default:
            return false
        }
    }

    // MARK: - Value Extraction

    /// Get the value as Int64, or nil if not an integer
    public var int64Value: Int64? {
        if case .int64(let v) = self { return v }
        return nil
    }

    /// Get the value as UInt64, or nil if not an unsigned integer.
    public var uint64Value: UInt64? {
        if case .uint64(let value) = self { return value }
        return nil
    }

    /// Get the value as Double, or nil if not a double
    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    /// Get the value as String, or nil if not a string
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    /// Get the value as Bool, or nil if not a boolean
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Get the value as Data, or nil if not binary data
    public var dataValue: DatabaseBytes? {
        if case .data(let v) = self { return v }
        return nil
    }

    public var rdfTermValue: DatabaseRDFTerm? {
        if case .rdfTerm(let value) = self { return value }
        return nil
    }

    /// Get the value as array, or nil if not an array
    public var arrayValue: [FieldValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    /// Get the numeric value as Double (works for both int64 and double)
    public var asDouble: Double? {
        switch self {
        case .int64(let v):
            return Double(v)
        case .uint64(let value):
            return Double(value)
        case .double(let v):
            return v
        default:
            return nil
        }
    }
}

// MARK: - Equatable

extension FieldValue: Equatable {
    /// Cross-type numeric equality without a lossy integer-to-double conversion.
    public static func == (lhs: FieldValue, rhs: FieldValue) -> Bool {
        switch (lhs, rhs) {
        case (.int64(let l), .int64(let r)): return l == r
        case (.uint64(let l), .uint64(let r)): return l == r
        case (.double(let l), .double(let r)): return l == r
        case (.string(let l), .string(let r)):
            return Self.utf8Equal(l, r)
        case (.bool(let l), .bool(let r)): return l == r
        case (.data(let l), .data(let r)): return l == r
        case (.rdfTerm(let l), .rdfTerm(let r)): return l == r
        case (.null, .null): return true
        case (.array(let l), .array(let r)): return l == r
        // Cross-type numeric equality
        case (.int64(let l), .double(let r)):
            return Self.integer(l, equals: r)
        case (.double(let l), .int64(let r)):
            return Self.integer(r, equals: l)
        case (.uint64(let l), .double(let r)):
            return Self.unsignedInteger(l, equals: r)
        case (.double(let l), .uint64(let r)):
            return Self.unsignedInteger(r, equals: l)
        case (.int64(let l), .uint64(let r)):
            return l >= 0 && UInt64(l) == r
        case (.uint64(let l), .int64(let r)):
            return r >= 0 && l == UInt64(r)
        default: return false
        }
    }
}

// MARK: - Hashable

extension FieldValue: Hashable {
    /// Cross-type consistent hashing
    ///
    /// Must be consistent with Equatable: if `a == b`, then `a.hashValue == b.hashValue`.
    /// Numerically equal signed, unsigned, and exactly integral floating-point
    /// values use one canonical integer representation. Integer values are never
    /// converted to `Double`, so adjacent values above 2^53 remain distinct inputs.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .int64(let v):
            Self.hashInteger(v, into: &hasher)
        case .uint64(let value):
            Self.hashUnsignedInteger(value, into: &hasher)
        case .double(let v):
            if let integer = Int64(exactly: v) {
                Self.hashInteger(integer, into: &hasher)
            } else if let integer = UInt64(exactly: v) {
                Self.hashUnsignedInteger(integer, into: &hasher)
            } else {
                hasher.combine(0)
                hasher.combine(2)
                hasher.combine(v.bitPattern)
            }
        case .string(let v):
            hasher.combine(1)
            hasher.combine(v.utf8.count)
            for byte in v.utf8 {
                hasher.combine(byte)
            }
        case .bool(let v):
            hasher.combine(2)
            hasher.combine(v)
        case .data(let v):
            hasher.combine(3)
            hasher.combine(v)
        case .rdfTerm(let value):
            hasher.combine(4)
            hasher.combine(value)
        case .null:
            hasher.combine(5)
        case .array(let v):
            hasher.combine(6)
            for element in v { hasher.combine(element) }
        }
    }

    private static func hashInteger(_ value: Int64, into hasher: inout Hasher) {
        if value >= 0 {
            hashUnsignedInteger(UInt64(value), into: &hasher)
            return
        }
        hasher.combine(0)
        hasher.combine(0)
        hasher.combine(value)
    }

    private static func hashUnsignedInteger(
        _ value: UInt64,
        into hasher: inout Hasher
    ) {
        hasher.combine(0)
        hasher.combine(1)
        hasher.combine(value)
    }
}

// MARK: - Comparable

extension FieldValue: Comparable {
    public static func < (lhs: FieldValue, rhs: FieldValue) -> Bool {
        switch (lhs, rhs) {
        // Same type comparisons
        case (.int64(let l), .int64(let r)):
            return l < r
        case (.uint64(let l), .uint64(let r)):
            return l < r
        case (.double(let l), .double(let r)):
            return l < r
        case (.string(let l), .string(let r)):
            return Self.utf8LessThan(l, r)
        case (.bool(let l), .bool(let r)):
            return !l && r  // false < true
        case (.data(let l), .data(let r)):
            return l.lexicographicallyPrecedes(r)
        case (.rdfTerm(let l), .rdfTerm(let r)):
            return l < r

        // Cross-type numeric comparisons
        case (.int64(let l), .double(let r)):
            return Self.integer(l, isLessThan: r)
        case (.double(let l), .int64(let r)):
            guard !l.isNaN, !Self.integer(r, equals: l) else {
                return false
            }
            return !Self.integer(r, isLessThan: l)
        case (.uint64(let l), .double(let r)):
            return Self.unsignedInteger(l, isLessThan: r)
        case (.double(let l), .uint64(let r)):
            guard !l.isNaN, !Self.unsignedInteger(r, equals: l) else {
                return false
            }
            return !Self.unsignedInteger(r, isLessThan: l)
        case (.int64(let l), .uint64(let r)):
            return l < 0 || UInt64(l) < r
        case (.uint64(let l), .int64(let r)):
            return r >= 0 && l < UInt64(r)

        // Null handling: null is less than everything else
        case (.null, .null):
            return false
        case (.null, _):
            return true
        case (_, .null):
            return false

        // Different non-comparable types: use type order
        default:
            return lhs.typeOrder < rhs.typeOrder
        }
    }

    /// Type ordering for cross-type comparison
    private var typeOrder: Int {
        switch self {
        case .null: return 0
        case .bool: return 1
        case .int64: return 2
        case .uint64: return 3
        case .double: return 4
        case .string: return 5
        case .rdfTerm: return 6
        case .data: return 7
        case .array: return 8
        }
    }

    private static func integer(_ integer: Int64, equals value: Double) -> Bool {
        guard value.isFinite, let exactInteger = Int64(exactly: value) else {
            return false
        }
        return integer == exactInteger
    }

    private static func integer(
        _ integer: Int64,
        isLessThan value: Double
    ) -> Bool {
        guard !value.isNaN else {
            return false
        }
        if value == .infinity {
            return true
        }
        if value == -.infinity {
            return false
        }

        let upperExclusive = 9_223_372_036_854_775_808.0
        let lowerInclusive = -9_223_372_036_854_775_808.0
        if value >= upperExclusive {
            return true
        }
        if value < lowerInclusive {
            return false
        }

        let truncated = Int64(value)
        if integer != truncated {
            return integer < truncated
        }
        return value > Double(truncated)
    }

    private static func unsignedInteger(
        _ integer: UInt64,
        equals value: Double
    ) -> Bool {
        guard value.isFinite, let exactInteger = UInt64(exactly: value) else {
            return false
        }
        return integer == exactInteger
    }

    private static func unsignedInteger(
        _ integer: UInt64,
        isLessThan value: Double
    ) -> Bool {
        guard !value.isNaN else {
            return false
        }
        if value == .infinity {
            return true
        }
        if value == -.infinity || value <= 0 {
            return false
        }

        let upperExclusive = 18_446_744_073_709_551_616.0
        if value >= upperExclusive {
            return true
        }

        let truncated = UInt64(value)
        if integer != truncated {
            return integer < truncated
        }
        return value > Double(truncated)
    }
}

// MARK: - CustomStringConvertible

extension FieldValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .int64(let v):
            return "int64(\(v))"
        case .uint64(let value):
            return "uint64(\(value))"
        case .double(let v):
            return "double(\(v))"
        case .string(let v):
            return "string(\"\(v)\")"
        case .bool(let v):
            return "bool(\(v))"
        case .data(let v):
            return "data(\(v.count) bytes)"
        case .rdfTerm(let value):
            return "rdfTerm(\(value))"
        case .null:
            return "null"
        case .array(let v):
            return "array(\(v))"
        }
    }
}

// MARK: - Codable

extension FieldValue {
    public init(from decoder: any Decoder) throws {
        let value = try DatabaseValue(from: decoder)
        guard let decoded = FieldValue(databaseValue: value) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported DatabaseValue for FieldValue"
                )
            )
        }
        self = decoded
    }

    public func encode(to encoder: any Encoder) throws {
        try asDatabaseValue.encode(to: encoder)
    }
}

// MARK: - Comparison Helpers

extension FieldValue {
    /// Check if this value equals another (convenience for predicate evaluation)
    public func isEqual(to other: FieldValue) -> Bool {
        self == other
    }

    /// Check if this value is less than another (convenience for predicate evaluation)
    public func isLessThan(_ other: FieldValue) -> Bool {
        self < other
    }

    /// Check if array contains a value (for IN predicates)
    public func contains(_ value: FieldValue) -> Bool {
        guard case .array(let values) = self else { return false }
        return values.contains(value)
    }

    /// Calculate numeric difference (self - other) if both are numeric
    ///
    /// Used for histogram bucket width calculation.
    public func numericDifference(from other: FieldValue) -> Double? {
        guard let lhs = asDouble, let rhs = other.asDouble else {
            return nil
        }
        return lhs - rhs
    }

    /// Compare two FieldValues for ordering
    ///
    /// Returns nil if the values are not comparable (different types except numeric)
    public func compare(to other: FieldValue) -> ComparisonResult? {
        if isNumeric && other.isNumeric {
            if self == other { return .orderedSame }
            if self < other { return .orderedAscending }
            if other < self { return .orderedDescending }
            return nil
        }
        switch (self, other) {
        case (.null, .null):
            return .orderedSame
        case (.null, _):
            return .orderedAscending  // NULL sorts first
        case (_, .null):
            return .orderedDescending

        case (.bool(let a), .bool(let b)):
            if a == b { return .orderedSame }
            return a ? .orderedDescending : .orderedAscending

        case (.string(let a), .string(let b)):
            if Self.utf8Equal(a, b) { return .orderedSame }
            return Self.utf8LessThan(a, b)
                ? .orderedAscending
                : .orderedDescending

        case (.data(let a), .data(let b)):
            for (i, byte) in a.enumerated() {
                if i >= b.count { return .orderedDescending }
                if byte < b[i] { return .orderedAscending }
                if byte > b[i] { return .orderedDescending }
            }
            if a.count < b.count { return .orderedAscending }
            return .orderedSame

        case (.rdfTerm(let a), .rdfTerm(let b)):
            if a == b { return .orderedSame }
            return a < b ? .orderedAscending : .orderedDescending

        default:
            return nil  // Incompatible types
        }
    }

    /// Database string semantics use the exact UTF-8 code units stored on the
    /// wire. Locale and Unicode normalization must not alter persistent order.
    private static func utf8Equal(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    private static func utf8LessThan(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}

// MARK: - FieldValueConvertible

/// Protocol for types that can be converted to FieldValue
///
/// Enables the predicate DSL to accept Swift native types and automatically
/// convert them to FieldValue at compile time.
public protocol FieldValueConvertible: Sendable {
    /// Convert this value to FieldValue
    func toFieldValue() -> FieldValue
}

// MARK: - Standard Type Conformances

extension Bool: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .bool(self) }
}

extension Int: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(Int64(self)) }
}

extension Int64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .int64(self) }
}

extension UInt: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt8: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt16: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt32: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(UInt64(self)) }
}

extension UInt64: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .uint64(self) }
}

extension Float: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .double(Double(self)) }
}

extension Double: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .double(self) }
}

extension String: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .string(self) }
}

extension Data: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .data(DatabaseBytes(retaining: RetainedDataByteOwner(data: self)))
    }
}

extension DatabaseRDFTerm: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .rdfTerm(self) }
}

extension UUID: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .string(uuidString.lowercased()) }
}

extension Date: FieldValueConvertible {
    public func toFieldValue() -> FieldValue { .double(timeIntervalSince1970) }
}

extension Array: FieldValueConvertible where Element: FieldValueConvertible {
    public func toFieldValue() -> FieldValue {
        .array(self.map { $0.toFieldValue() })
    }
}

// MARK: - Literal Expressibility

extension FieldValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension FieldValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .int64(value)
    }
}

extension FieldValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension FieldValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension FieldValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FieldValue...) {
        self = .array(elements)
    }
}

extension FieldValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
