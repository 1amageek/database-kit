import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Index scalar values")
struct IndexScalarValueTests {
    @Test("Every numeric runtime value has one stable scalar category")
    func numericScalarCategories() {
        assertNumericType(Int8.self, category: .int8)
        assertNumericType(Int16.self, category: .int16)
        assertNumericType(Int32.self, category: .int32)
        assertNumericType(Int64.self, category: .int64)
        assertNumericType(UInt8.self, category: .uint8)
        assertNumericType(UInt16.self, category: .uint16)
        assertNumericType(UInt32.self, category: .uint32)
        assertNumericType(UInt64.self, category: .uint64)
        assertNumericType(Float.self, category: .float32)
        assertNumericType(Double.self, category: .float64)
    }

    @Test("Every ordered nonnumeric runtime value has one stable category")
    func orderedScalarCategories() {
        assertComparableType(String.self, category: .string)
        assertComparableType(CivilDate.self, category: .date)
        assertComparableType(Timestamp.self, category: .timestamp)
    }

    @Test("Every index scalar round-trips through its canonical field value")
    func scalarValuesRoundTrip() throws {
        try assertRoundTrip(Int8(-8))
        try assertRoundTrip(Int16(-16))
        try assertRoundTrip(Int32(-32))
        try assertRoundTrip(Int64(-64))
        try assertRoundTrip(UInt8(8))
        try assertRoundTrip(UInt16(16))
        try assertRoundTrip(UInt32(32))
        try assertRoundTrip(UInt64(64))
        try assertRoundTrip(Float(1.25))
        try assertRoundTrip(Double(2.5))
        try assertRoundTrip("indexed")
        try assertRoundTrip(
            try CivilDate(year: 2026, month: 7, day: 27)
        )
        try assertRoundTrip(
            try Timestamp(
                secondsSinceUnixEpoch: 1_000,
                nanoseconds: 123
            )
        )
    }

    @Test("Scalar category capabilities match runtime dispatch")
    func scalarCategoryCapabilities() {
        let numeric: Set<IndexScalarType> = [
            .int8, .int16, .int32, .int64,
            .uint8, .uint16, .uint32, .uint64,
            .float32, .float64,
        ]

        for category in IndexScalarType.allCases {
            #expect(category.isNumeric == numeric.contains(category))
            #expect(
                category.isFloatingPoint
                    == (category == .float32 || category == .float64)
            )
        }
    }

    private func assertNumericType<Value: IndexNumericValue>(
        _ type: Value.Type,
        category: IndexScalarType
    ) {
        #expect(type.indexScalarType == category)
    }

    private func assertComparableType<Value: IndexComparableValue>(
        _ type: Value.Type,
        category: IndexScalarType
    ) {
        #expect(type.indexScalarType == category)
    }

    private func assertRoundTrip<Value: IndexComparableValue>(
        _ value: Value
    ) throws {
        #expect(
            try Value.decodeFieldValue(
                value.fieldValue,
                field: "value"
            ) == value
        )
    }
}
