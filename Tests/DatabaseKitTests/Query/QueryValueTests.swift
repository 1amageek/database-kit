import DatabaseKit
import DatabaseTypes
import Testing

@Suite("Lossless query values")
struct QueryValueTests {
    private var limits: QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: 4096, maximumTotalNodes: 100,
                         maximumNestingDepth: 16, maximumCollectionElements: 100)
    }

    @Test("Numeric display scale survives primitive canonicalization")
    func numericDisplayScale() throws {
        let value = try QueryNumericValue(value: ExactDecimal(coefficient: 100, scale: 2), displayScale: 2)
        #expect(value.value == ExactDecimal(coefficient: 1, scale: 0))
        #expect(value.displayScale == 2)
        #expect(try QueryNumericValue(value: ExactDecimal(coefficient: 0, scale: 0), displayScale: 16383).displayScale == 16383)
        #expect(throws: QueryValueError.invalidNumericDisplayScale(-1)) {
            try QueryNumericValue(value: value.value, displayScale: -1)
        }
        #expect(throws: QueryValueError.invalidNumericDisplayScale(16384)) {
            try QueryNumericValue(value: value.value, displayScale: 16384)
        }
        #expect(throws: QueryValueError.invalidNumericDisplayScale(1)) {
            try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 2), displayScale: 1)
        }
    }

    @Test("The coefficient budget includes negative Int128 boundary")
    func numericCoefficientBoundary() throws {
        let maximum = Int128("99999999999999999999999999999999999999")!
        #expect(try QueryNumericValue(value: ExactDecimal(coefficient: maximum, scale: 0), displayScale: 0).value.coefficient == maximum)
        #expect(throws: QueryValueError.numericOutOfRange) {
            try QueryNumericValue(value: ExactDecimal(coefficient: Int128.min, scale: 0), displayScale: 0)
        }
    }

    @Test("Array dimensions retain lower bounds and NULL cells")
    func arrayShape() throws {
        let dimensions = [try QueryArrayDimension(lowerBound: -2, length: 2),
                          try QueryArrayDimension(lowerBound: 4, length: 2)]
        let cells: [QueryValue] = [.primitive(.int32(1)), .primitive(.null),
                                   .primitive(.int32(3)), .primitive(.int32(4))]
        let value = try QueryArrayValue(elementType: .integer, dimensions: dimensions, elements: cells, limits: limits)
        #expect(value.dimensions.elementsEqual(dimensions))
        #expect(value.elements.elementsEqual(cells))
        let typed = try QueryArray<Int32>(arrayValue: value, limits: limits)
        #expect(typed.elements == [1, nil, 3, 4])
        #expect(typed.arrayValue == value)
    }

    @Test("Empty arrays retain their declared element type")
    func emptyArray() throws {
        let empty = try QueryArrayValue(elementType: .text, dimensions: [], elements: [], limits: limits)
        #expect(empty.elementType == .text)
        #expect(QueryValueValidator.accepts(.array(empty), type: .sql(.array(.text))))
        #expect(!QueryValueValidator.accepts(.array(empty), type: .sql(.array(.integer))))
    }

    @Test("Primitive optional-element arrays preserve NULL cells and reject incompatible cells")
    func primitiveArrayNullCells() throws {
        let elements: [Int64?] = [1, nil]
        let value = QueryValue.primitive(try elements.encodeFieldValue())
        let type = QueryColumnType.primitive(.int64, isArray: true)
        #expect(QueryValueValidator.accepts(value, type: type))
        try QueryValueValidator.validate(value, type: type, limits: limits)
        #expect(!QueryValueValidator.accepts(.primitive(.array([.int64(1), .string("wrong")])), type: type))
        #expect(!QueryValueValidator.accepts(.primitive(.int64(1)), type: type))
    }

    @Test("Wrong shape, element types and dimension overflow fail")
    func invalidArray() throws {
        let dimension = try QueryArrayDimension(lowerBound: 1, length: 2)
        #expect(throws: QueryValueError.elementCountMismatch(expected: 2, actual: 1)) {
            try QueryArrayValue(elementType: .integer, dimensions: [dimension], elements: [.primitive(.int32(1))], limits: limits)
        }
        #expect(throws: QueryValueError.elementTypeMismatch(index: 1)) {
            try QueryArrayValue(elementType: .integer, dimensions: [dimension], elements: [.primitive(.int32(1)), .primitive(.string("wrong"))], limits: limits)
        }
        #expect(throws: QueryValueError.invalidDimension(lowerBound: Int32.max, length: 2)) {
            try QueryArrayDimension(lowerBound: Int32.max, length: 2)
        }
        #expect(throws: QueryValueError.invalidDimension(lowerBound: 0, length: 0)) {
            try QueryArrayDimension(lowerBound: 0, length: 0)
        }
    }

    @Test("Six-dimensional shape accepts the boundary and rejects seven")
    func dimensionCountBoundary() throws {
        let one = try QueryArrayDimension(lowerBound: 1, length: 1)
        let value = try QueryArrayValue(elementType: .boolean, dimensions: [one, one, one, one, one, one], elements: [.primitive(.bool(true))], limits: limits)
        #expect(value.dimensions.count == 6)
        #expect(throws: QueryValueError.invalidDimensionCount(7)) {
            try QueryArrayValue(elementType: .boolean, dimensions: [one, one, one, one, one, one, one], elements: [.primitive(.bool(true))], limits: limits)
        }
    }

    @Test("Dimension product overflow is explicit")
    func dimensionProductOverflow() throws {
        let large = try QueryArrayDimension(lowerBound: 0, length: Int32.max)
        #expect(throws: QueryValueError.dimensionProductOverflow) {
            try QueryArrayValue(elementType: .integer, dimensions: [large, large, large], elements: [], limits: limits)
        }
    }

    @Test("Interval components stay separate and exact")
    func intervalComponents() throws {
        let value = try QueryIntervalValue(period: CalendarPeriod(months: -2, days: 3),
                                           time: TimeSpan(seconds: -1, nanoseconds: 500_000_000))
        #expect(value.period.months == -2)
        #expect(value.period.days == 3)
        #expect(value.microseconds == -500_000)
        #expect(value.time.seconds == -1)
    }

    @Test("Interval overflow and submicrosecond values fail")
    func intervalInvalid() throws {
        let zero = try TimeSpan(seconds: 0)
        #expect(throws: QueryValueError.intervalOutOfRange) {
            try QueryIntervalValue(period: CalendarPeriod(months: Int64(Int32.max) + 1), time: zero)
        }
        #expect(throws: QueryValueError.intervalOutOfRange) {
            try QueryIntervalValue(period: CalendarPeriod(), time: TimeSpan(seconds: 0, nanoseconds: 1))
        }
        #expect(throws: QueryValueError.intervalOutOfRange) {
            try QueryIntervalValue(period: CalendarPeriod(), time: TimeSpan(seconds: Int64.max))
        }
    }

    @Test("Columns preserve duplicate names while enforcing ordinal identity")
    func columnIdentity() throws {
        let columns = [try QueryColumn(number: 1, name: "x", type: .sql(.integer), isNullable: false),
                       try QueryColumn(number: 2, name: "x", type: .sql(.bigint), isNullable: true)]
        try QueryColumn.validate(columns)
        #expect(columns.map(\.name) == ["x", "x"])
        #expect(throws: QueryValueError.invalidColumnNumber(0)) {
            try QueryColumn(number: 0, name: "x", type: .sql(.text), isNullable: true)
        }
        #expect(throws: QueryValueError.invalidColumnNumber(2)) { try QueryColumn.validate([columns[1]]) }
        let composed = try QueryColumn(number: 1, name: "\u{E9}", type: .sql(.text), isNullable: false)
        let decomposed = try QueryColumn(number: 1, name: "e\u{301}", type: .sql(.text), isNullable: false)
        #expect(composed != decomposed)
    }

    @Test("Value budgets accept exact counts and reject one less")
    func valueLimits() throws {
        let value = try QueryArrayValue(elementType: .integer,
                                        dimensions: [QueryArrayDimension(lowerBound: 1, length: 2)],
                                        elements: [.primitive(.int32(1)), .primitive(.null)], limits: limits)
        let retained = try QueryValueValidator.measure(.array(value)).retainedByteCount
        let exact = QueryValueLimits(maximumRetainedBytes: retained, maximumTotalNodes: 3,
                                    maximumNestingDepth: 2, maximumCollectionElements: 2)
        try QueryValueValidator.validate(.array(value), limits: exact)
        #expect(throws: QueryValueError.resourceLimit(resource: "nodes", actual: 3, maximum: 2)) {
            try QueryValueValidator.validate(.array(value), limits: QueryValueLimits(maximumRetainedBytes: retained, maximumTotalNodes: 2, maximumNestingDepth: 2, maximumCollectionElements: 2))
        }
        let wide = try QueryArrayValue(
            elementType: .bigint, dimensions: [QueryArrayDimension(lowerBound: 1, length: 256)],
            elements: [QueryValue](repeating: .primitive(.null), count: 256),
            limits: QueryValueLimits(maximumRetainedBytes: 1_000_000, maximumTotalNodes: 258,
                                     maximumNestingDepth: 2, maximumCollectionElements: 256)
        )
        #expect(throws: QueryValueError.resourceLimit(resource: "collectionElements", actual: 256, maximum: 0)) {
            try QueryValueValidator.validate(.array(wide), limits: QueryValueLimits(
                maximumRetainedBytes: 1_000_000, maximumTotalNodes: 257, maximumNestingDepth: 2,
                maximumCollectionElements: 0
            ))
        }
    }

    @Test("Public retention counts aliases conservatively rather than claiming deduplication")
    func aliasedRetention() throws {
        let frame = ByteString(utf8: "nullnull")
        let capacity = UInt64(try #require(frame.retainedByteCount))
        let allowance = QueryValueLimits(maximumRetainedBytes: capacity, maximumTotalNodes: 10,
                                        maximumNestingDepth: 4, maximumCollectionElements: 10)
        let first = try QueryJSONValue(bytes: frame[0..<4], limits: allowance)
        let second = try QueryJSONValue(bytes: frame[4..<8], limits: allowance)
        #expect(try first.measure().retainedByteCount == capacity)
        #expect(try second.measure().retainedByteCount == capacity)
        let dimension = try QueryArrayDimension(lowerBound: 1, length: 2)
        #expect(throws: QueryValueError.self) {
            try QueryArrayValue(elementType: .json, dimensions: [dimension],
                                elements: [.json(first), .json(second)], limits: allowance)
        }
        let assembled = try QueryArrayValue(admittedElementType: .json, dimensions: [dimension],
                                             elements: [.json(first), .json(second)])
        #expect(assembled.elements.count == 2)
        #expect(assembled.storageFootprint.leafRetainedByteCount == capacity * 2)
        #expect(try QueryValueValidator.measure(.array(assembled)).retainedByteCount > capacity * 2)
        #expect(throws: QueryValueError.elementCountMismatch(expected: 2, actual: 1)) {
            try QueryArrayValue(admittedElementType: .json, dimensions: [dimension], elements: [.json(first)])
        }
        #expect(throws: QueryValueError.elementTypeMismatch(index: 1)) {
            try QueryArrayValue(admittedElementType: .json, dimensions: [dimension],
                                elements: [.json(first), .primitive(.int32(1))])
        }
    }

    @Test("Unknown capacity fails instead of using visible bytes as a physical bound")
    func unknownRetention() throws {
        let source = ByteString(retaining: QueryUnknownRetentionOwner())
        #expect(source.count == 4)
        #expect(source.retainedByteCount == nil)
        #expect(throws: QueryValueError.unknownRetainedByteCount) {
            try QueryValueValidator.validate(.primitive(.bytes(source)), limits: limits)
        }
        let owned = ByteString.copying(count: source.count) { output in
            source.withUnsafeBytes { output.copyMemory(from: $0) }
        }
        try QueryValueValidator.validate(.primitive(.bytes(owned)), limits: limits)
        #expect(try QueryValueValidator.measure(.primitive(.bytes(owned))).retainedByteCount == UInt64(try #require(owned.retainedByteCount)))
    }
}

private struct QueryUnknownRetentionOwner: ByteStringOwner {
    private let bytes = ByteString(utf8: "null")
    var count: Int { bytes.count }

    func borrowBytes(_ body: (UnsafeRawBufferPointer) throws -> Void) rethrows {
        try bytes.withUnsafeBytes(body)
    }
}
