import DatabaseTypes
import DatabaseValue
import Testing

@Suite("XSD Date Time Codec")
struct XSDDateTimeCodecTests {
    @Test func formatsCanonicalDatesWithoutIntermediateFormattingObjects() throws {
        #expect(
            XSDDateTimeCodec.format(
                date: try CivilDate(year: 2026, month: 7, day: 20)
            ) == "2026-07-20"
        )
        #expect(
            XSDDateTimeCodec.format(
                date: try CivilDate(year: 10_000, month: 1, day: 2)
            ) == "10000-01-02"
        )
        #expect(
            XSDDateTimeCodec.format(
                date: try CivilDate(year: 0, month: 2, day: 29)
            ) == "0000-02-29"
        )
    }

    @Test func rejectsInvalidAndNonCanonicalDateLexicalForms() throws {
        #expect(
            XSDDateTimeCodec.parseDate("2024-02-29")
                == (try CivilDate(year: 2024, month: 2, day: 29))
        )
        #expect(XSDDateTimeCodec.parseDate("2023-02-29") == nil)
        #expect(XSDDateTimeCodec.parseDate("02026-07-20") == nil)
        #expect(XSDDateTimeCodec.parseDate("2026-7-20") == nil)
        #expect(XSDDateTimeCodec.parseDate("2026-07-20Z") == nil)
    }

    @Test func formatsCanonicalUTCTimestamps() throws {
        #expect(
            try XSDDateTimeCodec.format(
                timestamp: Timestamp(secondsSinceUnixEpoch: 0)
            ) == "1970-01-01T00:00:00Z"
        )
        #expect(
            try XSDDateTimeCodec.format(
                timestamp: try Timestamp(
                    secondsSinceUnixEpoch: -1,
                    nanoseconds: 120_000_000
                )
            ) == "1969-12-31T23:59:59.12Z"
        )
    }

    @Test func normalizesOffsetsAndEndOfDayWithoutPrecisionLoss() {
        let normalized = XSDDateTimeCodec.parseTimestamp(
            "2026-07-20T05:30:00Z"
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T14:30:00+09:00"
            ) == normalized
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T24:00:00Z"
            ) == XSDDateTimeCodec.parseTimestamp(
                "2026-07-21T00:00:00Z"
            )
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.1234567890Z"
            ) == XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.123456789Z"
            )
        )
    }

    @Test func rejectsTimestampValuesThatCannotBeRepresentedExactly() {
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T24:00:00.000000001Z"
            ) == nil
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.1234567891Z"
            ) == nil
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00"
            ) == nil
        )
        #expect(
            XSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00+14:01"
            ) == nil
        )
    }

    @Test func rejectsInvalidPrimitiveValuesAtConstruction() {
        #expect(
            throws: CivilDateError.invalidDay(
                29,
                year: 2026,
                month: 2,
                maximum: 28
            )
        ) {
            _ = try CivilDate(year: 2026, month: 2, day: 29)
        }
        #expect(
            throws: TimestampError.invalidNanoseconds(1_000_000_000)
        ) {
            _ = try Timestamp(
                secondsSinceUnixEpoch: 0,
                nanoseconds: 1_000_000_000
            )
        }
    }

    @Test func rejectsTimestampsOutsideTheXSDYearRange() throws {
        #expect(throws: XSDDateTimeError.self) {
            try XSDDateTimeCodec.format(
                timestamp: Timestamp(
                    secondsSinceUnixEpoch: .max
                )
            )
        }
    }
}
