import DatabaseTypes
import Testing
@testable import DatabaseKit

@Suite("FieldValue Tests")
struct FieldValueTests {
    @Test("Representable values provide a total canonical conversion")
    func representableValuesEncodeWithoutFailure() throws {
        #expect(canonicalValue(Int16(-12)) == .int16(-12))
        #expect(
            canonicalValue([UInt8(1), UInt8(2)])
                == .array([.uint8(1), .uint8(2)])
        )
        #expect(canonicalValue(Optional<String>.none) == .null)
    }

    @Test("Unsigned Swift scalars preserve their exact values")
    func unsignedIntegerInitializersPreserveExactValues() {
        #expect(UInt.max.encodeFieldValue() == .uint64(UInt64(UInt.max)))
        #expect(UInt8.max.encodeFieldValue() == .uint8(UInt8.max))
        #expect(UInt16.max.encodeFieldValue() == .uint16(UInt16.max))
        #expect(UInt32.max.encodeFieldValue() == .uint32(UInt32.max))
        #expect(UInt64.max.encodeFieldValue() == .uint64(UInt64.max))
    }

    @Test("Every fixed-width numeric type retains a distinct storage identity")
    func fixedWidthNumericTypesRetainDistinctIdentity() {
        let values: [FieldValue] = [
            .int8(1),
            .int16(1),
            .int32(1),
            .int64(1),
            .uint8(1),
            .uint16(1),
            .uint32(1),
            .uint64(1),
            .float32(1),
            .float64(1),
        ]

        #expect(Set(values).count == values.count)
        #expect(FieldValue.float32(-0.0) != .float32(0.0))
        #expect(FieldValue.float64(-0.0) != .float64(0.0))
    }

    @Test("Stored numeric types preserve distinct identity")
    func storedNumericIdentityIsExact() {
        let zero: [FieldValue] = [.int64(0), .uint64(0), .float64(-0.0)]
        #expect(Set(zero).count == 3)

        let signedBoundary: [FieldValue] = [
            .int64(Int64.max),
            .uint64(UInt64(Int64.max)),
        ]
        #expect(Set(signedBoundary).count == 2)

        let unsignedDoubleBoundary = UInt64(1) << 63
        let unsignedAndDouble: [FieldValue] = [
            .uint64(unsignedDoubleBoundary),
            .float64(Double(unsignedDoubleBoundary)),
        ]
        #expect(Set(unsignedAndDouble).count == 2)

        #expect(FieldValue.int64(0).compare(to: .uint64(0)) == .equal)
        #expect(
            FieldValue.uint64(unsignedDoubleBoundary).compare(
                to: .float64(Double(unsignedDoubleBoundary))
            ) == .equal
        )
    }

    @Test("Adjacent UInt64 values above 2^53 remain distinct")
    func adjacentLargeUnsignedValuesRemainDistinct() {
        let exactDoubleBoundary = UInt64(1) << 53
        let adjacent = exactDoubleBoundary + 1
        let rounded = Double(adjacent)

        #expect(rounded == Double(exactDoubleBoundary))
        #expect(FieldValue.uint64(adjacent) != .float64(rounded))
        #expect(FieldValue.uint64(exactDoubleBoundary) != .float64(rounded))
        #expect(FieldValue.uint64(exactDoubleBoundary) < .uint64(adjacent))
        #expect(FieldValue.uint64(adjacent) < .float64(rounded))
        #expect(
            FieldValue.uint64(exactDoubleBoundary).compare(to: .float64(rounded))
                == .equal
        )
        #expect(
            FieldValue.uint64(adjacent).compare(to: .float64(rounded))
                == .greaterThan
        )

        #expect(
            Set([
                FieldValue.uint64(exactDoubleBoundary),
                .uint64(adjacent),
            ]).count == 2
        )
    }

    @Test("UInt64 upper boundary has exact ordering")
    func uint64UpperBoundaryOrderingIsExact() {
        let penultimate = FieldValue.uint64(UInt64.max - 1)
        let maximum = FieldValue.uint64(UInt64.max)
        let roundedBeyondMaximum = FieldValue.float64(Double(UInt64.max))

        #expect(FieldValue.int64(-1) < .uint64(0))
        #expect(FieldValue.int64(Int64.max) < .uint64(UInt64(Int64.max) + 1))
        #expect(penultimate < maximum)
        #expect(maximum < roundedBeyondMaximum)
        #expect(maximum != roundedBeyondMaximum)
        #expect(maximum.compare(to: penultimate) == .greaterThan)
        #expect(maximum.compare(to: roundedBeyondMaximum) == .lessThan)
    }

    // MARK: - Initialization

    @Test("Init from Int64")
    func testInitInt64() {
        let value = FieldValue.int64(42)
        #expect(value.int64Value == 42)
        #expect(value.isNumeric == true)
        #expect(value.isNull == false)
    }

    @Test("Init from Double")
    func testInitDouble() {
        let value = FieldValue.float64(3.14)
        #expect(value.float64Value == 3.14)
        #expect(value.isNumeric == true)
        #expect(value.isNull == false)
    }

    @Test("Init from String")
    func testInitString() {
        let value = FieldValue.string("hello")
        #expect(value.stringValue == "hello")
        #expect(value.isNumeric == false)
        #expect(value.isNull == false)
    }

    @Test("Init from Bool")
    func testInitBool() {
        let trueValue = FieldValue.bool(true)
        let falseValue = FieldValue.bool(false)

        #expect(trueValue.boolValue == true)
        #expect(falseValue.boolValue == false)
        #expect(trueValue.isNumeric == false)
    }

    @Test("Init from Data")
    func testInitData() {
        let data: ByteString = [1, 2, 3, 4]
        let value = FieldValue.bytes(data)

        #expect(value.bytesValue == data)
        #expect(value.isNumeric == false)
    }

    @Test("Init null")
    func testInitNull() {
        let value = FieldValue.null

        #expect(value.isNull == true)
        #expect(value.isNumeric == false)
        #expect(value.int64Value == nil)
        #expect(value.stringValue == nil)
    }

    // MARK: - Conversion

    @Test("Convert from Int")
    func testConvertInt() {
        let value = (42 as Int).encodeFieldValue()
        #expect(value.int64Value == 42)
    }

    @Test("Convert from Int32")
    func testConvertInt32() {
        let value = Int32(42).encodeFieldValue()
        #expect(value.int32Value == 42)
    }

    @Test("Convert from Float")
    func testConvertFloat() {
        let value = Float(3.14).encodeFieldValue()
        #expect(value.float32Value != nil)
    }

    @Test("Optional conversion preserves value and absence")
    func optionalConversionPreservesValueAndAbsence() throws {
        let present: String? = "calendar"
        let absent: String? = nil
        let presentValue = try present.encodeFieldValue()
        let absentValue = try absent.encodeFieldValue()

        #expect(presentValue == .string("calendar"))
        #expect(absentValue == .null)
    }

    // MARK: - Numeric projection

    @Test("query numeric difference projects int64")
    func testNumericDifferenceInt64() {
        let value = FieldValue.int64(42)
        #expect(value.numericDifference(from: .int64(0)) == 42.0)
    }

    @Test("query numeric difference projects float64")
    func testNumericDifferenceDouble() {
        let value = FieldValue.float64(3.14)
        #expect(value.numericDifference(from: .float64(0)) == 3.14)
    }

    @Test("query numeric difference rejects non-numeric values")
    func testNumericDifferenceNonNumeric() {
        let value = FieldValue.string("hello")
        #expect(value.numericDifference(from: .int64(0)) == nil)
    }

    // MARK: - Comparable

    @Test("Int64 comparison")
    func testInt64Comparison() {
        let a = FieldValue.int64(10)
        let b = FieldValue.int64(20)

        #expect(a < b)
        #expect(!(b < a))
        #expect(a == FieldValue.int64(10))
    }

    @Test("Double comparison")
    func testDoubleComparison() {
        let a = FieldValue.float64(1.5)
        let b = FieldValue.float64(2.5)

        #expect(a < b)
        #expect(!(b < a))
    }

    @Test("Decimal identity uses its normalized canonical value")
    func decimalIdentityUsesNormalizedValue() {
        let onePointZero = FieldValue.decimal(
            ExactDecimal(coefficient: 10, scale: 1)
        )
        let onePointZeroZero = FieldValue.decimal(
            ExactDecimal(coefficient: 100, scale: 2)
        )

        #expect(onePointZero == onePointZeroZero)
        #expect(!(onePointZero < onePointZeroZero))
        #expect(!(onePointZeroZero < onePointZero))
    }

    @Test("String comparison")
    func testStringComparison() {
        let a = FieldValue.string("apple")
        let b = FieldValue.string("banana")

        #expect(a < b)
        #expect(!(b < a))
    }

    @Test("String equality and ordering use exact UTF-8 code units")
    func stringComparisonUsesExactUTF8CodeUnits() {
        let composed = FieldValue.string("\u{00e9}")
        let decomposed = FieldValue.string("e\u{0301}")

        #expect(composed != decomposed)
        #expect(decomposed < composed)
        #expect(decomposed.compare(to: composed) == .lessThan)
    }

    @Test("Bool comparison (false < true)")
    func testBoolComparison() {
        let falseVal = FieldValue.bool(false)
        let trueVal = FieldValue.bool(true)

        #expect(falseVal < trueVal)
        #expect(!(trueVal < falseVal))
    }

    @Test("Data comparison (lexicographic)")
    func testDataComparison() {
        let a = FieldValue.bytes([1, 2, 3])
        let b = FieldValue.bytes([1, 2, 4])

        #expect(a < b)
    }

    @Test("Null is less than everything")
    func testNullComparison() {
        let nullVal = FieldValue.null
        let intVal = FieldValue.int64(0)
        let strVal = FieldValue.string("")

        #expect(nullVal < intVal)
        #expect(nullVal < strVal)
        #expect(!(intVal < nullVal))
    }

    @Test("Cross-type numeric comparison")
    func testCrossTypeNumericComparison() {
        let intVal = FieldValue.int64(10)
        let doubleVal = FieldValue.float64(10.5)

        #expect(intVal < doubleVal)
        #expect(!(doubleVal < intVal))
    }

    // MARK: - Hashable

    @Test("Same values have same hash")
    func testHashableSameValues() {
        let a = FieldValue.string("test")
        let b = FieldValue.string("test")

        #expect(a.hashValue == b.hashValue)
    }

    @Test("Can be used in Set")
    func testSetUsage() {
        var set: Set<FieldValue> = []
        set.insert(.int64(1))
        set.insert(.int64(2))
        set.insert(.int64(1))  // Duplicate

        #expect(set.count == 2)
    }

    @Test("Can be used as Dictionary key")
    func testDictionaryUsage() {
        var dict: [FieldValue: String] = [:]
        dict[.string("key1")] = "value1"
        dict[.string("key2")] = "value2"

        #expect(dict[.string("key1")] == "value1")
        #expect(dict[.string("key2")] == "value2")
    }

    @Test("query numeric comparison does not alter stored identity")
    func queryNumericComparisonPreservesStoredIdentity() {
        let exactInteger = FieldValue.int64(42)
        let exactDouble = FieldValue.float64(42)
        let roundedInteger = FieldValue.int64(9_007_199_254_740_993)
        let roundedDouble = FieldValue.float64(9_007_199_254_740_992)

        #expect(exactInteger != exactDouble)
        #expect(exactInteger.compare(to: exactDouble) == .equal)
        #expect(roundedInteger != roundedDouble)
        #expect(roundedInteger.compare(to: roundedDouble) == .greaterThan)
    }

    private func canonicalValue<Value: FieldValueRepresentable>(
        _ value: borrowing Value
    ) -> FieldValue {
        value.encodeFieldValue()
    }
}
