import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL temporal values", .timeLimit(.minutes(1)))
struct SQLTemporalValueTests {
    @Test func timeBoundsAndIdentity() throws {
        let midnight = try QueryTimeValue(microsecondsSinceMidnight: 0)
        let endpoint = try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000)
        #expect(midnight != endpoint)
        #expect(Set([midnight, endpoint, midnight]).count == 2)
        for value: Int64 in [-1, 86_400_000_001, .min, .max] {
            #expect(throws: QueryValueError.timeOutOfRange) {
                _ = try QueryTimeValue(microsecondsSinceMidnight: value)
            }
        }
        let primitive = QueryValue.primitive(.time(try CivilTime(hour: 0, minute: 0, second: 0)))
        #expect(primitive != .time(midnight))
        #expect(QueryValueValidator.accepts(primitive, type: .sql(.time(withTimeZone: false))))
        #expect(QueryValueValidator.accepts(.time(endpoint), type: .sql(.time(withTimeZone: false))))
    }

    @Test func timeZoneFullWidthOffsetIdentity() throws {
        let time = try QueryTimeValue(microsecondsSinceMidnight: 12_000_000)
        let values = [Int32.min, -57_600, 0, 57_600, Int32.max].map {
            QueryTimeWithTimeZoneValue(time: time, utcOffsetSeconds: $0)
        }
        #expect(Set(values).count == values.count)
        for value in values {
            #expect(QueryValueValidator.accepts(.timeWithTimeZone(value), type: .sql(.time(withTimeZone: true))))
            #expect(!QueryValueValidator.accepts(.timeWithTimeZone(value), type: .sql(.time(withTimeZone: false))))
        }
    }

    @Test func infinityFamilyAndPrecisionAdmission() throws {
        for sign: QueryTemporalInfinity in [.negative, .positive] {
            for precision: Int? in [nil, 0, 1, 2, 3, 4, 5, 6] {
                #expect(QueryValueValidator.accepts(.timestampInfinity(sign, withTimeZone: true),
                    type: .sql(.timestamp(withTimeZone: true, precision: precision))))
                #expect(!QueryValueValidator.accepts(.timestampInfinity(sign, withTimeZone: true),
                    type: .sql(.timestamp(withTimeZone: false, precision: precision))))
                #expect(QueryValueValidator.accepts(.intervalInfinity(sign),
                    type: .sql(.interval(fields: .dayToSecond, precision: precision))))
            }
            #expect(QueryValueValidator.accepts(.dateInfinity(sign), type: .sql(.date)))
            #expect(!QueryValueValidator.accepts(.dateInfinity(sign), type: .primitive(.date)))
            #expect(!QueryValueValidator.accepts(.dateInfinity(sign), type: .sql(.interval())))
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
                _ = try Literal.queryValue(.dateInfinity(sign), type: .sql(.date)).toSPARQL()
            }
        }
        #expect(Set([QueryValue.dateInfinity(.negative), .dateInfinity(.positive),
                     .timestampInfinity(.positive, withTimeZone: false),
                     .timestampInfinity(.positive, withTimeZone: true), .intervalInfinity(.positive)]).count == 5)
        for value: QueryValue in [.time(try QueryTimeValue(microsecondsSinceMidnight: 0)),
            .timeWithTimeZone(QueryTimeWithTimeZoneValue(time: try QueryTimeValue(microsecondsSinceMidnight: 0),
                                                       utcOffsetSeconds: 0)),
            .dateInfinity(.positive), .timestampInfinity(.positive, withTimeZone: true), .intervalInfinity(.positive)] {
            #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) {
                _ = try Literal.queryValue(value).toSPARQL()
            }
            #expect(throws: SPARQLSemanticValidationError.unsupportedQueryValue) {
                try SPARQLSemanticValidator.validate(.filter(.basic([]), .literal(.queryValue(value))))
            }
        }
        let modified = DataType.interval(fields: .dayToSecond, precision: 3)
        #expect(throws: QueryLiteralConversionError.unsupportedSPARQLLiteral) { _ = try modified.sparqlFunction }
        #expect(throws: SPARQLSemanticValidationError.unsupportedSQLExpression) {
            try SPARQLSemanticValidator.validate(.filter(.basic([]), .cast(.int(1), targetType: modified)))
        }
    }

    @Test func finiteDeclaredRangeAndPrecision() throws {
        for (year, month, day, accepted): (Int32, UInt8, UInt8, Bool) in [
            (-4713, 11, 23, false), (-4713, 11, 24, true),
            (5_874_897, 12, 31, true), (5_874_898, 1, 1, false)] {
            let value = QueryValue.primitive(.date(try CivilDate(year: year, month: month, day: day)))
            #expect(QueryValueValidator.accepts(value, type: .sql(.date)) == accepted)
            #expect(QueryValueValidator.accepts(value, type: .primitive(.date)))
        }
        let lower: Int64 = -211_813_488_000_000_000 / 1_000_000 + 946_684_800
        let upper: Int64 = 9_223_371_331_200_000_000 / 1_000_000 + 946_684_800
        for (seconds, accepted) in [(lower - 1, false), (lower, true), (upper - 1, true), (upper, false)] {
            let value = QueryValue.primitive(.timestamp(Timestamp(secondsSinceUnixEpoch: seconds)))
            #expect(QueryValueValidator.accepts(value, type: .sql(.timestamp(withTimeZone: true))) == accepted)
            #expect(QueryValueValidator.accepts(value, type: .primitive(.timestamp)))
        }
        let nano = QueryValue.primitive(.timestamp(try Timestamp(secondsSinceUnixEpoch: 946_684_800, nanoseconds: 1)))
        #expect(!QueryValueValidator.accepts(nano, type: .sql(.timestamp(withTimeZone: true))))
        #expect(QueryValueValidator.accepts(nano, type: .primitive(.timestamp)))
        let fractional = QueryValue.time(try QueryTimeValue(microsecondsSinceMidnight: 1))
        #expect(!QueryValueValidator.accepts(fractional, type: .sql(.time(withTimeZone: false, precision: 5))))
        #expect(QueryValueValidator.accepts(fractional, type: .sql(.time(withTimeZone: false, precision: 6))))
        let year = QueryValue.interval(try QueryIntervalValue(period: CalendarPeriod(months: 12), time: TimeSpan(seconds: 0)))
        #expect(QueryValueValidator.accepts(year, type: .sql(.interval(fields: .year))))
        let month = QueryValue.interval(try QueryIntervalValue(period: CalendarPeriod(months: 13), time: TimeSpan(seconds: 0)))
        #expect(!QueryValueValidator.accepts(month, type: .sql(.interval(fields: .year))))
        #expect(!QueryValueValidator.accepts(.primitive(.null), type: .sql(.interval(fields: .day, precision: 2))))
        #expect(!QueryValueValidator.accepts(.primitive(.null), type: .sql(.interval(precision: 7))))
    }
}
