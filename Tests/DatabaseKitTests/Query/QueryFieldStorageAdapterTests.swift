import DatabaseTypes
import DatabaseKit
import Testing

@Suite("Declared query field storage adaptation")
struct QueryFieldStorageAdapterTests {
    private let limits = QueryValueLimits(maximumRetainedBytes: 1_000_000,
                                          maximumTotalNodes: 10_000,
                                          maximumNestingDepth: 100,
                                          maximumCollectionElements: 10_000)

    @Test("numeric envelopes preserve observable display scale")
    func numericRoundTrip() throws {
        let value = QueryValue.numeric(try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 2), displayScale: 6))
        try roundTrip(value, type: .sql(.decimal(precision: nil, scale: nil)))
        let payload = try QueryFieldStorageAdapter.encode(value, type: .sql(.decimal(precision: nil, scale: nil)), limits: limits)
        guard case .object(let fields) = payload else { Issue.record("Missing numeric envelope"); return }
        #expect(fields["displayScale"] == .int32(6))
        let measured = try QueryFieldStorageAdapter.measure(value, type: .sql(.decimal(precision: nil, scale: nil)))
        #expect(measured.valueNodes == 4)
        #expect(measured.objectEntries == 3)
        #expect(measured.newUTF8Bytes == 28)
        #expect(measured.maximumDepth == 2)
    }

    @Test("lexical JSON and normalized JSONB have distinct lossless envelopes")
    func jsonRoundTrip() throws {
        let json = try QueryJSONValue(bytes: ByteString(utf8: " {\"b\":1.00, \"a\":null, \"b\":2.000} "), limits: limits)
        try roundTrip(.json(json), type: .sql(.json))
        let jsonb = try QueryJSONBValue(json: json, limits: limits)
        try roundTrip(.jsonb(jsonb), type: .sql(.jsonb))
        try roundTrip(.jsonb(try QueryJSONBValue(root: .null, limits: limits)), type: .sql(.jsonb))
        let measured = try QueryFieldStorageAdapter.measure(.json(json), type: .sql(.json))
        #expect(measured.retainedByteViewCount == 1)
        #expect(measured.retainedByteViewLength == UInt64(json.bytes.count))
    }

    @Test("array declaration preserves shape, lower bounds, NULL and rich elements")
    func arrayRoundTrip() throws {
        let number = try QueryNumericValue(value: ExactDecimal(coefficient: 42, scale: 1), displayScale: 3)
        let type = DataType.decimal(precision: nil, scale: nil)
        let array = try QueryArrayValue(elementType: type,
                                        dimensions: [QueryArrayDimension(lowerBound: -2, length: 2)],
                                        elements: [.numeric(number), .primitive(.null)], limits: limits)
        try roundTrip(.array(array), type: .sql(.array(type)))
        let empty = try QueryArrayValue(elementType: .integer, dimensions: [], elements: [], limits: limits)
        try roundTrip(.array(empty), type: .sql(.array(.integer)))
    }

    @Test("interval microseconds preserve negative fractions and independent months/days")
    func intervalRoundTrip() throws {
        let interval = try QueryIntervalValue(period: CalendarPeriod(months: 5, days: -7),
                                              time: TimeSpan(seconds: -1, nanoseconds: 999_999_000))
        #expect(interval.microseconds == -1)
        try roundTrip(.interval(interval), type: .sql(.interval()))
    }

    @Test("ordinary objects and bytes retain primitive meaning")
    func primitiveRoundTrip() throws {
        let payload = try object([("kind", .string("json")), ("bytes", .bytes(ByteString(utf8: "null")))])
        let value = QueryValue.primitive(payload)
        try roundTrip(value, type: .primitive(.object))
        #expect(try QueryFieldStorageAdapter.encode(value, type: .primitive(.object), limits: limits) == payload)
        try roundTrip(.primitive(.null), type: .sql(.json))
    }

    @Test("unknown, extra, missing, mismatched and lossy numeric payloads fail")
    func corruptedEnvelopes() throws {
        let type = QueryColumnType.sql(.decimal(precision: nil, scale: nil))
        let invalid: [FieldValue] = [
            try object([("kind", .string("unknown")), ("value", .decimal(ExactDecimal(coefficient: 1, scale: 0))), ("displayScale", .int32(0))]),
            try object([("kind", .string("numeric")), ("value", .decimal(ExactDecimal(coefficient: 1, scale: 0))), ("displayScale", .int32(0)), ("extra", .null)]),
            try object([("kind", .string("numeric")), ("value", .decimal(ExactDecimal(coefficient: 1, scale: 0)))]),
            try object([("kind", .string("numeric")), ("value", .int64(1)), ("displayScale", .int32(0))]),
            try object([("kind", .string("numeric")), ("value", .decimal(ExactDecimal(coefficient: 123, scale: 2))), ("displayScale", .int32(1))]),
            try object([("kind", .string("numeric")), ("value", .decimal(ExactDecimal(coefficient: 0, scale: 0))), ("displayScale", .int32(16_384))])
        ]
        for payload in invalid {
            #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(payload, type: type, limits: limits) }
        }
    }

    @Test("malformed JSON, JSONB node layouts and array shapes fail")
    func malformedStructuredPayloads() throws {
        let malformedJSON = try object([("kind", .string("json")), ("bytes", .bytes(ByteString(utf8: "[1,")))])
        #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(malformedJSON, type: .sql(.json), limits: limits) }
        let malformedNode = try object([("kind", .string("jsonb")), ("root", object([("kind", .string("null")), ("value", .null)]))])
        #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(malformedNode, type: .sql(.jsonb), limits: limits) }
        let malformedArray = try object([("kind", .string("array")),
                                         ("dimensions", .array([object([("lowerBound", .int32(1)), ("length", .int32(2))])])),
                                         ("elements", .array([.int32(1)]))])
        #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(malformedArray, type: .sql(.array(.integer)), limits: limits) }
    }

    @Test("exact envelope budgets reject one-past counts before construction")
    func envelopeBudget() throws {
        let type = QueryColumnType.sql(.decimal(precision: nil, scale: nil))
        let value = QueryValue.numeric(try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 0))
        let exact = QueryValueLimits(maximumRetainedBytes: 28, maximumTotalNodes: 4,
                                     maximumNestingDepth: 2, maximumCollectionElements: 3)
        let payload = try QueryFieldStorageAdapter.encode(value, type: type, limits: exact)
        #expect(try QueryFieldStorageAdapter.decode(payload, type: type, limits: exact) == value)
        let tooFew = QueryValueLimits(maximumRetainedBytes: 28, maximumTotalNodes: 3,
                                      maximumNestingDepth: 2, maximumCollectionElements: 3)
        #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.encode(value, type: type, limits: tooFew) }
        #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(payload, type: type, limits: tooFew) }
    }

    @Test("no-budget model adaptation derives finite limits from owned structure")
    func inferredBounds() throws {
        let value = QueryValue.json(try QueryJSONValue(bytes: ByteString(utf8: "[[[[[null]]]]]"), limits: limits))
        let bounds = try QueryFieldStorageAdapter.inferredLimits(for: value, type: .sql(.json))
        let payload = try QueryFieldStorageAdapter.encode(value, type: .sql(.json), limits: bounds)
        let decodedBounds = try QueryFieldStorageAdapter.inferredLimits(for: payload, type: .sql(.json))
        #expect(try QueryFieldStorageAdapter.decode(payload, type: .sql(.json), limits: decodedBounds) == value)
    }

    @Test("flat JSONB prefix payloads reject invalid tree grammar and layouts")
    func prefixMalformedPayloads() throws {
        let null = try object([("kind", .string("null"))])
        let array = try object([("kind", .string("array")), ("childCount", .uint64(2))])
        let duplicate = try object([("kind", .string("object")), ("keys", .array([.string("a"), .string("a")]))])
        let unordered = try object([("kind", .string("object")), ("keys", .array([.string("b"), .string("a")]))])
        let invalid: [[FieldValue]] = [
            [], [array, null], [null, null],
            [try object([("kind", .string("array")), ("childCount", .int64(0))])],
            [try object([("kind", .string("array")), ("childCount", .uint64(UInt64.max))])],
            [try object([("kind", .string("null")), ("extra", .null)])],
            [try object([("kind", .string("unknown"))])],
            [duplicate, null, null], [unordered, null, null],
            [try object([("kind", .string("object")), ("keys", .array([.int32(1)]))]), null]
        ]
        for records in invalid {
            let payload = try object([("kind", .string("jsonb")), ("nodes", .array(records))])
            #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.measureDecoded(payload, type: .sql(.jsonb)) }
            #expect(throws: QueryValueError.self) { try QueryFieldStorageAdapter.decode(payload, type: .sql(.jsonb), limits: limits) }
        }
    }

    @Test("deep JSONB envelope measurement uses bounded iterative traversal")
    func deepJSONBMeasurement() throws {
        let deepLimits = QueryValueLimits(maximumRetainedBytes: 1_000_000,
                                          maximumTotalNodes: 2_000,
                                          maximumNestingDepth: 600,
                                          maximumCollectionElements: 2_000)
        let text = String(repeating: "[", count: 256) + "null" + String(repeating: ",null]", count: 256)
        let json = try QueryJSONValue(bytes: ByteString(utf8: text), limits: deepLimits)
        let value = QueryValue.jsonb(try QueryJSONBValue(json: json, limits: deepLimits))
        let measured = try QueryFieldStorageAdapter.measure(value, type: .sql(.jsonb))
        #expect(measured.valueNodes == 1_285)
        #expect(measured.objectEntries == 771)
        #expect(measured.arrayElements == 513)
        #expect(measured.newUTF8Bytes == 6_934)
        #expect(measured.maximumDepth == 4)
    }

    @Test("deep JSONB wrappers persist and decode through iterative parent frames")
    func deepJSONBRoundTrip() throws {
        let number = try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 2), displayScale: 6)
        var text = ""
        for level in stride(from: 4_095, through: 0, by: -1) {
            text += level.isMultiple(of: 2) ? "[" : "{\"a\":"
        }
        text += "1.230000"
        for level in 0..<4_096 { text += level.isMultiple(of: 2) ? ",null]" : ",\"b\":true}" }
        let deepLimits = QueryValueLimits(maximumRetainedBytes: 4_000_000,
                                          maximumTotalNodes: 10_000,
                                          maximumNestingDepth: 5_000,
                                          maximumCollectionElements: 10_000)
        let json = try QueryJSONValue(bytes: ByteString(utf8: text), limits: deepLimits)
        let original = try QueryJSONBValue(json: json, limits: deepLimits)
        let payload = try original.encodeFieldValue()
        let destination = try QueryFieldStorageAdapter.measureDecoded(payload, type: .sql(.jsonb))
        #expect(destination.nodeCount == 8_193)
        #expect(destination.jsonbNodeCount == 8_193)
        #expect(destination.jsonbElementIndexCount == 4_096)
        #expect(destination.jsonbMemberCount == 4_096)
        #expect(destination.maximumNestingDepth == 4_097)
        let decoded = try QueryJSONBValue.decodeFieldValue(payload, field: "deepJSONB")
        var current = decoded.root
        for level in stride(from: 4_095, through: 0, by: -1) {
            if level.isMultiple(of: 2) {
                guard case .array(let elements) = current, elements.count == 2,
                      case .null = elements[1] else { Issue.record("Array shape or sibling changed"); return }
                current = elements[0]
            } else {
                guard case .object(let members) = current, members.count == 2,
                      members[0].key == "a", members[1].key == "b",
                      case .bool(true) = members[1].value else { Issue.record("Object order or sibling changed"); return }
                current = members[0].value
            }
        }
        guard case .number(let result) = current else { Issue.record("Numeric leaf changed"); return }
        #expect(result.value == number.value)
        #expect(result.displayScale == 6)
    }

    private func roundTrip(_ value: QueryValue, type: QueryColumnType) throws {
        let payload = try QueryFieldStorageAdapter.encode(value, type: type, limits: limits)
        #expect(try QueryFieldStorageAdapter.decode(payload, type: type, limits: limits) == value)
    }

    private func object(_ fields: [(key: String, value: FieldValue)]) throws -> FieldValue {
        .object(try FieldObject(fields))
    }
}
