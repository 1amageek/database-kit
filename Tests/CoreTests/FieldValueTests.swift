import DatabaseTypes
import Testing
import Foundation
import DatabaseValue
@testable import Core

@Suite("FieldValue Tests")
struct FieldValueTests {
    @Test("Unsigned Swift scalars preserve their exact values")
    func unsignedIntegerInitializersPreserveExactValues() {
        #expect(UInt.max.toFieldValue() == .uint64(UInt64(UInt.max)))
        #expect(UInt8.max.toFieldValue() == .uint8(UInt8.max))
        #expect(UInt16.max.toFieldValue() == .uint16(UInt16.max))
        #expect(UInt32.max.toFieldValue() == .uint32(UInt32.max))
        #expect(UInt64.max.toFieldValue() == .uint64(UInt64.max))
    }

    @Test("Every fixed-width numeric type retains a distinct storage identity")
    func fixedWidthNumericTypesRetainDistinctIdentity() throws {
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
        #expect(try Set(values.map { try $0.stableHash() }).count == values.count)
        #expect(FieldValue.float32(-0.0) != .float32(0.0))
        #expect(FieldValue.float64(-0.0) != .float64(0.0))
    }

    @Test("UInt64 survives FieldValue and Codable round trips")
    func uint64RoundTripsWithoutNarrowing() throws {
        let original = FieldValue.array([
            .uint64(0),
            .uint64(UInt64(Int64.max)),
            .uint64(UInt64(Int64.max) + 1),
            .uint64(UInt64.max),
        ])

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FieldValue.self, from: encoded)
        #expect(decoded == original)
    }

    @Test("Stored numeric types preserve distinct identity and hashes")
    func storedNumericIdentityIsExact() throws {
        let zero: [FieldValue] = [.int64(0), .uint64(0), .float64(-0.0)]
        #expect(Set(zero).count == 3)
        #expect(try Set(zero.map { try $0.stableHash() }).count == 3)

        let signedBoundary: [FieldValue] = [
            .int64(Int64.max),
            .uint64(UInt64(Int64.max)),
        ]
        #expect(Set(signedBoundary).count == 2)
        #expect(
            try Set(signedBoundary.map { try $0.stableHash() }).count == 2
        )

        let unsignedDoubleBoundary = UInt64(1) << 63
        let unsignedAndDouble: [FieldValue] = [
            .uint64(unsignedDoubleBoundary),
            .float64(Double(unsignedDoubleBoundary)),
        ]
        #expect(Set(unsignedAndDouble).count == 2)
        #expect(
            try Set(unsignedAndDouble.map { try $0.stableHash() }).count == 2
        )

        #expect(FieldValue.int64(0).compare(to: .uint64(0)) == .orderedSame)
        #expect(
            FieldValue.uint64(unsignedDoubleBoundary).compare(
                to: .float64(Double(unsignedDoubleBoundary))
            ) == .orderedSame
        )
    }

    @Test("Adjacent UInt64 values above 2^53 remain distinct")
    func adjacentLargeUnsignedValuesRemainDistinct() throws {
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
                == .orderedSame
        )
        #expect(
            FieldValue.uint64(adjacent).compare(to: .float64(rounded))
                == .orderedDescending
        )

        #expect(
            try FieldValue.uint64(exactDoubleBoundary).stableHash()
                != FieldValue.uint64(adjacent).stableHash()
        )
        #expect(
            Set([
                FieldValue.uint64(exactDoubleBoundary),
                .uint64(adjacent),
            ]).count == 2
        )
    }

    @Test("UInt64 upper boundary has exact ordering")
    func uint64UpperBoundaryOrderingIsExact() throws {
        let penultimate = FieldValue.uint64(UInt64.max - 1)
        let maximum = FieldValue.uint64(UInt64.max)
        let roundedBeyondMaximum = FieldValue.float64(Double(UInt64.max))

        #expect(FieldValue.int64(-1) < .uint64(0))
        #expect(FieldValue.int64(Int64.max) < .uint64(UInt64(Int64.max) + 1))
        #expect(penultimate < maximum)
        #expect(maximum < roundedBeyondMaximum)
        #expect(maximum != roundedBeyondMaximum)
        #expect(maximum.compare(to: penultimate) == .orderedDescending)
        #expect(maximum.compare(to: roundedBeyondMaximum) == .orderedAscending)
        let penultimateHash = try penultimate.stableHash()
        let maximumHash = try maximum.stableHash()
        #expect(penultimateHash != maximumHash)
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
        let value = (42 as Int).toFieldValue()
        #expect(value.int64Value == 42)
    }

    @Test("Convert from Int32")
    func testConvertInt32() {
        let value = Int32(42).toFieldValue()
        #expect(value.int32Value == 42)
    }

    @Test("Convert from Float")
    func testConvertFloat() {
        let value = Float(3.14).toFieldValue()
        #expect(value.float32Value != nil)
    }

    @Test("Optional conversion preserves value and absence")
    func optionalConversionPreservesValueAndAbsence() throws {
        let present: String? = "calendar"
        let absent: String? = nil
        let presentValue = try present.toFieldValue()
        let absentValue = try absent.toFieldValue()

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
        #expect(decomposed.compare(to: composed) == .orderedAscending)
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

    // MARK: - Codable

    @Test("Encode and decode int64")
    func testCodableInt64() throws {
        let original = FieldValue.int64(42)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let restored = try decoder.decode(FieldValue.self, from: data)

        #expect(original == restored)
    }

    @Test("Encode and decode all types")
    func testCodableAllTypes() throws {
        let values: [FieldValue] = [
            .int64(42),
            .float64(3.14),
            .string("hello"),
            .bool(true),
            .bytes([1, 2, 3]),
            .null
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in values {
            let data = try encoder.encode(original)
            let restored = try decoder.decode(FieldValue.self, from: data)
            #expect(original == restored)
        }
    }

    // MARK: - Stable Hash

    @Test("Stable hash is deterministic")
    func testStableHashDeterministic() throws {
        let value = FieldValue.string("test")

        let hash1 = try value.stableHash()
        let hash2 = try value.stableHash()

        #expect(hash1 == hash2)
    }

    @Test("Different types produce different hashes")
    func testStableHashDifferentTypes() throws {
        let intVal = FieldValue.int64(1)
        let strVal = FieldValue.string("1")

        let integerHash = try intVal.stableHash()
        let stringHash = try strVal.stableHash()
        #expect(integerHash != stringHash)
    }

    @Test("RDF stable hash is deterministic and semantic")
    func testRDFStableHash() throws {
        let first = FieldValue.rdfTerm(
            try .iri(validating: "urn:database:first")
        )
        let same = FieldValue.rdfTerm(
            try .iri(validating: "urn:database:first")
        )
        let different = FieldValue.rdfTerm(
            try .blankNode(identifier: "urn:database:first")
        )

        let firstHash = try first.stableHash()
        let sameHash = try same.stableHash()
        let differentHash = try different.stableHash()
        #expect(firstHash == sameHash)
        #expect(firstHash != differentHash)
    }

    @Test("RDF language-tag identity and stable hash are consistent")
    func testRDFLanguageTagStableHash() throws {
        let uppercase = FieldValue.rdfTerm(.literal(RDFLiteral(
            lexicalForm: "hello",
            language: try RDFLanguageTag("EN-Latn-US")
        )))
        let lowercase = FieldValue.rdfTerm(.literal(RDFLiteral(
            lexicalForm: "hello",
            language: try RDFLanguageTag("en-latn-us")
        )))

        #expect(uppercase == lowercase)
        let uppercaseHash = try uppercase.stableHash()
        let lowercaseHash = try lowercase.stableHash()
        #expect(uppercaseHash == lowercaseHash)
    }

    @Test("Stable hash for all types")
    func testStableHashAllTypes() throws {
        let values: [FieldValue] = [
            .int64(42),
            .float64(3.14),
            .string("hello"),
            .bool(true),
            .bytes([1, 2, 3]),
            .null
        ]

        var hashes: Set<UInt64> = []
        for value in values {
            let hash = try value.stableHash()
            hashes.insert(hash)
        }

        // All values should have unique hashes
        #expect(hashes.count == values.count)
    }

    @Test("query numeric comparison does not alter stored identity")
    func queryNumericComparisonPreservesStoredIdentity() throws {
        let exactInteger = FieldValue.int64(42)
        let exactDouble = FieldValue.float64(42)
        let roundedInteger = FieldValue.int64(9_007_199_254_740_993)
        let roundedDouble = FieldValue.float64(9_007_199_254_740_992)

        #expect(exactInteger != exactDouble)
        let exactIntegerHash = try exactInteger.stableHash()
        let exactDoubleHash = try exactDouble.stableHash()
        #expect(exactIntegerHash != exactDoubleHash)
        #expect(exactInteger.compare(to: exactDouble) == .orderedSame)
        #expect(roundedInteger != roundedDouble)
        let roundedIntegerHash = try roundedInteger.stableHash()
        let roundedDoubleHash = try roundedDouble.stableHash()
        #expect(roundedIntegerHash != roundedDoubleHash)
        #expect(roundedInteger.compare(to: roundedDouble) == .orderedDescending)
    }
}
