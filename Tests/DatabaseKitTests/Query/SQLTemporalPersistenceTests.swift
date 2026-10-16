import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL temporal persistence", .timeLimit(.minutes(1)))
struct SQLTemporalPersistenceTests {
    private let limits = QueryValueLimits(maximumRetainedBytes: 4096, maximumTotalNodes: 100,
        maximumNestingDepth: 16, maximumCollectionElements: 100)

    private func envelope(_ fields: [(String, FieldValue)]) throws -> FieldValue {
        .object(try FieldObject(fields.map { (key: $0.0, value: $0.1) }))
    }

    private func roundTrip(_ value: QueryValue, type: DataType) throws -> FieldValue {
        let payload = try QueryFieldStorageAdapter.encode(value, type: .sql(type), limits: limits)
        #expect(try QueryFieldStorageAdapter.decode(payload, type: .sql(type), limits: limits) == value)
        return payload
    }

    @Test func distinctTimeAndPrimitiveRoundTrips() throws {
        let primitive = FieldValue.time(try CivilTime(hour: 0, minute: 0, second: 0))
        #expect(try roundTrip(.primitive(primitive), type: .time(withTimeZone: false)) == primitive)
        for microseconds: Int64 in [0, 1, 86_399_999_999, 86_400_000_000] {
            let value = QueryValue.time(try QueryTimeValue(microsecondsSinceMidnight: microseconds))
            let expected = try envelope([("kind", .string("time")), ("microseconds", .int64(microseconds))])
            #expect(try roundTrip(value, type: .time(withTimeZone: false)) == expected)
        }
    }

    @Test func temporalInfinityAndOffsetRoundTrips() throws {
        for sign: QueryTemporalInfinity in [.negative, .positive] {
            _ = try roundTrip(.dateInfinity(sign), type: .date)
            for zone in [false, true] {
                _ = try roundTrip(.timestampInfinity(sign, withTimeZone: zone),
                                  type: .timestamp(withTimeZone: zone, precision: 0))
            }
            _ = try roundTrip(.intervalInfinity(sign), type: .interval(fields: .year))
        }
        for offset in [Int32.min, 0, Int32.max] {
            _ = try roundTrip(.timeWithTimeZone(QueryTimeWithTimeZoneValue(
                time: QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000), utcOffsetSeconds: offset)),
                type: .time(withTimeZone: true))
        }
        let date = FieldValue.date(try CivilDate(year: 2024, month: 2, day: 29))
        #expect(try roundTrip(.primitive(date), type: .date) == date)
        let timestamp = FieldValue.timestamp(Timestamp(secondsSinceUnixEpoch: 0))
        #expect(try roundTrip(.primitive(timestamp), type: .timestamp(withTimeZone: true)) == timestamp)
    }

    @Test func strictDeclaredEnvelopeFailures() throws {
        let invalid = [
            try envelope([("kind", .string("time")), ("microseconds", .int64(-1))]),
            try envelope([("kind", .string("time")), ("microseconds", .int32(0))]),
            try envelope([("kind", .string("time")), ("microseconds", .int64(0)), ("extra", .null)]),
        ]
        for payload in invalid {
            #expect(throws: QueryValueError.self) {
                _ = try QueryFieldStorageAdapter.decode(payload, type: .sql(.time(withTimeZone: false)), limits: limits)
            }
        }
        for sign: FieldValue in [.int8(0), .int8(2), .int64(1), .null] {
            let payload = try envelope([("kind", .string("dateInfinity")), ("sign", sign)])
            #expect(throws: QueryValueError.self) {
                _ = try QueryFieldStorageAdapter.decode(payload, type: .sql(.date), limits: limits)
            }
        }
        let raw = try envelope([("kind", .string("dateInfinity")), ("sign", .int8(1))])
        #expect(try QueryFieldStorageAdapter.decode(raw, type: .primitive(.object), limits: limits) == .primitive(raw))
        #expect(throws: QueryValueError.self) {
            _ = try QueryFieldStorageAdapter.decode(raw, type: .sql(.timestamp(withTimeZone: true)), limits: limits)
        }
        #expect(throws: QueryValueError.incompatibleType) {
            _ = try QueryFieldStorageAdapter.encode(.timestampInfinity(.positive, withTimeZone: true),
                type: .sql(.timestamp(withTimeZone: false)), limits: limits)
        }
    }

    @Test func retainedResourceBoundaries() throws {
        let value = QueryValue.time(try QueryTimeValue(microsecondsSinceMidnight: 1))
        // One object, two scalar children, and kind/time/microseconds UTF-8 bytes.
        let exact = QueryValueLimits(maximumRetainedBytes: 20, maximumTotalNodes: 3,
                                    maximumNestingDepth: 2, maximumCollectionElements: 2)
        let payload = try QueryFieldStorageAdapter.encode(value, type: .sql(.time(withTimeZone: false)), limits: exact)
        #expect(try QueryFieldStorageAdapter.decode(payload, type: .sql(.time(withTimeZone: false)), limits: exact) == value)
        let short = QueryValueLimits(maximumRetainedBytes: exact.maximumRetainedBytes,
            maximumTotalNodes: exact.maximumTotalNodes - 1, maximumNestingDepth: exact.maximumNestingDepth,
            maximumCollectionElements: exact.maximumCollectionElements)
        #expect(throws: QueryValueError.resourceLimit(resource: "totalNodes", actual: 3, maximum: 2)) {
            _ = try QueryFieldStorageAdapter.encode(value, type: .sql(.time(withTimeZone: false)), limits: short)
        }
        #expect(throws: QueryValueError.resourceLimit(resource: "totalNodes", actual: 3, maximum: 2)) {
            _ = try QueryFieldStorageAdapter.decode(payload, type: .sql(.time(withTimeZone: false)), limits: short)
        }
        #expect(try QueryValueValidator.measure(value).nodeCount == 1)
        #expect(try QueryValueValidator.measure(value).retainedByteCount == 0)
    }
}
