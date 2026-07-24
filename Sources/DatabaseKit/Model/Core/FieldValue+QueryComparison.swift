import DatabaseTypes
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension FieldValue {
    public var isNumeric: Bool {
        switch self {
        case .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .decimal:
            return true
        default:
            return false
        }
    }

    public func isEqual(to other: FieldValue) -> Bool {
        compare(to: other) == .orderedSame
    }

    public func isLessThan(_ other: FieldValue) -> Bool {
        compare(to: other) == .orderedAscending
    }

    public func numericDifference(from other: FieldValue) -> Double? {
        guard let left = queryNumericDoubleValue,
              let right = other.queryNumericDoubleValue else {
            return nil
        }
        return left - right
    }

    /// Query comparison for scalar field values.
    ///
    /// Persisted value identity remains exact; numeric coercion is applied only
    /// while evaluating a query comparison.
    public func compare(to other: FieldValue) -> ComparisonResult? {
        if isNumeric, other.isNumeric {
            return compareNumeric(to: other)
        }
        switch (self, other) {
        case (.null, .null):
            return .orderedSame
        case (.null, _):
            return .orderedAscending
        case (_, .null):
            return .orderedDescending
        case (.bool(let left), .bool(let right)):
            if left == right { return .orderedSame }
            return left ? .orderedDescending : .orderedAscending
        case (.string(let left), .string(let right)):
            if utf8Equal(left, right) {
                return .orderedSame
            }
            return utf8LessThan(left, right)
                ? .orderedAscending
                : .orderedDescending
        case (.bytes(let left), .bytes(let right)):
            if left == right { return .orderedSame }
            return left.lexicographicallyPrecedes(right)
                ? .orderedAscending
                : .orderedDescending
        case (.date(let left), .date(let right)):
            return order(left, right)
        case (.time(let left), .time(let right)):
            return order(left, right)
        case (.dateTime(let left), .dateTime(let right)):
            return order(left, right)
        case (.timestamp(let left), .timestamp(let right)):
            return order(left, right)
        case (.timeSpan(let left), .timeSpan(let right)):
            return order(left, right)
        case (.calendarPeriod(let left), .calendarPeriod(let right)):
            return order(left, right)
        case (.geographicPoint(let left), .geographicPoint(let right)):
            return order(left, right)
        case (.geographicPosition(let left), .geographicPosition(let right)):
            return order(left, right)
        case (.vector(let left), .vector(let right)):
            return order(left, right)
        case (.uuid(let left), .uuid(let right)):
            return order(left, right)
        case (.array(let left), .array(let right)):
            if left == right { return .orderedSame }
            return left.lexicographicallyPrecedes(right)
                ? .orderedAscending
                : .orderedDescending
        case (.object(let left), .object(let right)):
            return order(left, right)
        case (.reference(let left), .reference(let right)):
            return order(left, right)
        case (.rdfTerm(let left), .rdfTerm(let right)):
            return order(left, right)
        default:
            return nil
        }
    }

    private func compareNumeric(to other: FieldValue) -> ComparisonResult? {
        let leftValue = widenedNumericValue
        let rightValue = other.widenedNumericValue
        switch (leftValue, rightValue) {
        case (.int64(let left), .int64(let right)):
            return order(left, right)
        case (.uint64(let left), .uint64(let right)):
            return order(left, right)
        case (.float64(let left), .float64(let right)):
            guard !left.isNaN, !right.isNaN else { return nil }
            return order(left, right)
        case (.int64(let left), .uint64(let right)):
            if left < 0 { return .orderedAscending }
            return order(UInt64(left), right)
        case (.uint64(let left), .int64(let right)):
            if right < 0 { return .orderedDescending }
            return order(left, UInt64(right))
        case (.int64(let left), .float64(let right)):
            return Self.compare(left, to: right)
        case (.float64(let left), .int64(let right)):
            return Self.compare(right, to: left)?.reversed
        case (.uint64(let left), .float64(let right)):
            return Self.compare(left, to: right)
        case (.float64(let left), .uint64(let right)):
            return Self.compare(right, to: left)?.reversed
        case (.decimal(let left), .decimal(let right)):
            return comparisonResult(left.compare(to: right))
        case (.decimal, .int64), (.decimal, .uint64),
             (.int64, .decimal), (.uint64, .decimal):
            guard let left = exactDecimalValue,
                  let right = other.exactDecimalValue else {
                return Self.compareFiniteNumericFallback(self, other)
            }
            return comparisonResult(left.compare(to: right))
        case (.decimal, .float64), (.float64, .decimal):
            return Self.compareFiniteNumericFallback(leftValue, rightValue)
        default:
            return nil
        }
    }

    private var widenedNumericValue: FieldValue {
        switch self {
        case .int8(let value):
            return .int64(Int64(value))
        case .int16(let value):
            return .int64(Int64(value))
        case .int32(let value):
            return .int64(Int64(value))
        case .uint8(let value):
            return .uint64(UInt64(value))
        case .uint16(let value):
            return .uint64(UInt64(value))
        case .uint32(let value):
            return .uint64(UInt64(value))
        case .float32(let value):
            return .float64(Double(value))
        default:
            return self
        }
    }

    private func comparisonResult(_ value: Int) -> ComparisonResult {
        if value < 0 { return .orderedAscending }
        if value > 0 { return .orderedDescending }
        return .orderedSame
    }

    private func order<Value: Comparable>(
        _ left: Value,
        _ right: Value
    ) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if right < left { return .orderedDescending }
        return .orderedSame
    }

    private static func compare(
        _ integer: Int64,
        to value: Double
    ) -> ComparisonResult? {
        guard !value.isNaN else { return nil }
        if value == .infinity { return .orderedAscending }
        if value == -.infinity { return .orderedDescending }

        let upperExclusive = 9_223_372_036_854_775_808.0
        let lowerInclusive = -9_223_372_036_854_775_808.0
        if value >= upperExclusive { return .orderedAscending }
        if value < lowerInclusive { return .orderedDescending }

        let truncated = Int64(value)
        if integer < truncated { return .orderedAscending }
        if integer > truncated { return .orderedDescending }
        if value > Double(truncated) { return .orderedAscending }
        return .orderedSame
    }

    private static func compare(
        _ integer: UInt64,
        to value: Double
    ) -> ComparisonResult? {
        guard !value.isNaN else { return nil }
        if value == .infinity { return .orderedAscending }
        if value == -.infinity || value < 0 { return .orderedDescending }

        let upperExclusive = 18_446_744_073_709_551_616.0
        if value >= upperExclusive { return .orderedAscending }

        let truncated = UInt64(value)
        if integer < truncated { return .orderedAscending }
        if integer > truncated { return .orderedDescending }
        if value > Double(truncated) { return .orderedAscending }
        return .orderedSame
    }

    private static func compareFiniteNumericFallback(
        _ left: FieldValue,
        _ right: FieldValue
    ) -> ComparisonResult? {
        guard let left = left.queryNumericDoubleValue,
              let right = right.queryNumericDoubleValue,
              left.isFinite,
              right.isFinite else {
            return nil
        }
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }

    private var exactDecimalValue: ExactDecimal? {
        switch self {
        case .int8(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .int16(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .int32(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .int64(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .uint8(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .uint16(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .uint32(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .uint64(let value):
            return ExactDecimal(coefficient: Int128(value), scale: 0)
        case .decimal(let value):
            return value
        default:
            return nil
        }
    }

    private var queryNumericDoubleValue: Double? {
        switch self {
        case .int8(let value): return Double(value)
        case .int16(let value): return Double(value)
        case .int32(let value): return Double(value)
        case .int64(let value): return Double(value)
        case .uint8(let value): return Double(value)
        case .uint16(let value): return Double(value)
        case .uint32(let value): return Double(value)
        case .uint64(let value): return Double(value)
        case .float32(let value): return Double(value)
        case .float64(let value): return value
        case .decimal(let value):
            let magnitude = Self.powerOfTen(
                UInt32(value.scale >= 0 ? Int64(value.scale) : -Int64(value.scale))
            )
            return value.scale >= 0
                ? Double(value.coefficient) / magnitude
                : Double(value.coefficient) * magnitude
        default:
            return nil
        }
    }

    private static func powerOfTen(_ exponent: UInt32) -> Double {
        var exponent = exponent
        var factor = 10.0
        var result = 1.0
        while exponent > 0 {
            if exponent & 1 == 1 {
                result *= factor
            }
            exponent >>= 1
            if exponent > 0 {
                factor *= factor
            }
        }
        return result
    }

    private func utf8Equal(_ left: String, _ right: String) -> Bool {
        left.utf8.elementsEqual(right.utf8)
    }

    private func utf8LessThan(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending:
            return .orderedDescending
        case .orderedSame:
            return .orderedSame
        case .orderedDescending:
            return .orderedAscending
        }
    }
}

extension FieldValue: @retroactive ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension FieldValue: @retroactive ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .int64(value)
    }
}

extension FieldValue: @retroactive ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .float64(value)
    }
}

extension FieldValue: @retroactive ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension FieldValue: @retroactive ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FieldValue...) {
        self = .array(elements)
    }
}

extension FieldValue: @retroactive ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
