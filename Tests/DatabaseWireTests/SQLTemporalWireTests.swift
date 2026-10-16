import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("SQL temporal Wire grammar")
struct SQLTemporalWireTests {
    @Test func temporalValueGoldens() throws {
        let zero = try QueryTimeValue(microsecondsSinceMidnight: 0)
        let cases: [(QueryValue, ByteString)] = [
            (.time(zero), ByteString([6] + Array(repeating: 0, count: 8))),
            (.timeWithTimeZone(.init(time: zero, utcOffsetSeconds: .min)), ByteString([7] + Array(repeating: 0, count: 8) + [0, 0, 0, 128])),
            (.dateInfinity(.positive), [8, 1]), (.timestampInfinity(.negative, withTimeZone: true), [9, 0, 1]),
            (.intervalInfinity(.positive), [10, 1]),
        ]
        for (value, golden) in cases {
            #expect(try encode(value) == golden)
            var reader = DatabaseWireReader(golden)
            #expect(try QueryValueWireCodec.decode(from: &reader) == value)
            try reader.ensureFullyRead()
            var lazy = DatabaseWireReader(golden)
            try QueryValueWireCodec.validate(from: &lazy)
            try lazy.ensureFullyRead()
            for end in 0..<golden.count { try rejectValue(ByteString(Array(golden[0..<end]))) }
        }
        let endpoint = QueryValue.time(try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000))
        var reader = DatabaseWireReader(try encode(endpoint))
        #expect(try QueryValueWireCodec.decode(from: &reader) == endpoint)
    }

    @Test func intervalDescriptorGoldens() throws {
        #expect(try encodeType(.interval()) == ByteString([13]))
        #expect(try encodeType(.interval(precision: 0)) == ByteString([25, 0, 1, 0]))
        #expect(try encodeType(.interval(fields: .dayToSecond, precision: 3)) == ByteString([25, 1, 9, 1, 3]))
        for fields in SQLIntervalFields.allCases {
            let type = DataType.interval(fields: fields)
            let bytes = try encodeType(type)
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRDataTypeWireCodec.decode(from: &reader) == type)
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) {
                    var truncated = DatabaseWireReader(ByteString(Array(bytes[0..<end])))
                    _ = try QueryIRDataTypeWireCodec.decode(from: &truncated)
                }
            }
        }
        for bytes: ByteString in [[25, 0, 0], [25, 1, 13], [25, 2], [25, 0, 1, 7], [25, 1, 0, 1, 3]] {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(bytes)
                _ = try QueryIRDataTypeWireCodec.decode(from: &reader)
            }
        }
    }

    @Test func currentValueGoldensAndFailures() throws {
        for (index, kind) in SQLCurrentValueKind.allCases.enumerated() {
            let value = Expression.currentValue(kind: kind, precision: nil)
            let bytes = try encodeExpression(value)
            #expect(bytes == ByteString([52, UInt8(index), 0]))
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRWireFormat.decodeExpression(from: &reader) == value)
            if kind != .date {
                #expect(try encodeExpression(.currentValue(kind: kind, precision: 6)) == ByteString([52, UInt8(index), 1, 6]))
            }
        }
        for bytes: ByteString in [[52], [52, 5], [52, 1, 2], [52, 1, 1], [52, 1, 1, 7], [52, 0, 1, 0]] {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(bytes)
                _ = try QueryIRWireFormat.decodeExpression(from: &reader)
            }
        }
        let generic = Expression.function(FunctionCall(name: "current_date", arguments: []))
        #expect(try encodeExpression(generic).first == 28)
    }

    @Test func typedLazyArrayAndNullCarriage() throws {
        let type = DataType.interval(fields: .dayToSecond, precision: 3)
        let array = try QueryArrayValue(elementType: type,
            dimensions: [QueryArrayDimension(lowerBound: -2, length: 2)],
            elements: [.intervalInfinity(.negative), .primitive(.null)], limits: DatabaseWireLimits.default.queryValueLimits)
        let value = QueryValue.array(array)
        let bytes = try encode(value)
        var reader = DatabaseWireReader(bytes)
        #expect(try QueryValueWireCodec.decode(from: &reader) == value)
        var lazy = DatabaseWireReader(bytes)
        try QueryValueWireCodec.validate(from: &lazy, type: .sql(.array(type)))
        var wrong = DatabaseWireReader(try encode(.timestampInfinity(.positive, withTimeZone: true)))
        #expect(throws: DatabaseWireError.invalidQueryValue(.incompatibleType)) {
            try QueryValueWireCodec.validate(from: &wrong, type: .sql(.timestamp(withTimeZone: false)))
        }
        var null = DatabaseWireReader(try encode(.primitive(.null)))
        try QueryValueWireCodec.validate(from: &null, type: .sql(type))
        for malformed: ByteString in [[8, 2], [9, 0, 2], [10, 255], ByteString([6] + Array(repeating: 255, count: 8))] {
            try rejectValue(malformed)
        }
    }

    @Test func temporalBudgetsAndOperationCarriage() throws {
        let query = QueryStatement.select(SelectQuery(projection: [ProjectionItem(.currentValue(kind: .timestamp, precision: 3))], source: .values([])))
        #expect(try QueryIRWireFormat.decode(QueryIRWireFormat.encode(query)) == query)
        let value = QueryValue.time(try QueryTimeValue(microsecondsSinceMidnight: 1))
        let exact = try DatabaseWireLimits(maximumFrameBytes: 9, maximumStringBytes: 9, maximumByteStringBytes: 9, maximumCollectionCount: 8, maximumNestingDepth: 8, maximumObjectCount: 8)
        #expect(try DatabaseWireWriter.encode(limits: exact) { writer throws(DatabaseWireError) in try QueryValueWireCodec.encode(value, into: &writer) }.count == 9)
        let short = try DatabaseWireLimits(maximumFrameBytes: 8, maximumStringBytes: 8, maximumByteStringBytes: 8, maximumCollectionCount: 8, maximumNestingDepth: 8, maximumObjectCount: 8)
        #expect(throws: DatabaseWireError.self) {
            _ = try DatabaseWireWriter.encode(limits: short) { writer throws(DatabaseWireError) in try QueryValueWireCodec.encode(value, into: &writer) }
        }
    }

    private func encode(_ value: QueryValue) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryValueWireCodec.encode(value, into: &writer) }
    }
    private func encodeType(_ type: DataType) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryIRDataTypeWireCodec.encode(type, into: &writer) }
    }
    private func encodeExpression(_ value: Expression) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode { writer throws(DatabaseWireError) in try QueryIRWireFormat.encodeExpression(value, into: &writer) }
    }
    private func rejectValue(_ bytes: ByteString) throws {
        #expect(throws: DatabaseWireError.self) { var reader = DatabaseWireReader(bytes); _ = try QueryValueWireCodec.decode(from: &reader) }
        #expect(throws: DatabaseWireError.self) { var reader = DatabaseWireReader(bytes); try QueryValueWireCodec.validate(from: &reader) }
    }
}
