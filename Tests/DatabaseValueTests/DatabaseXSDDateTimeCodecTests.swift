import DatabaseValue
import Testing

@Suite("Database XSD Date Time Codec")
struct DatabaseXSDDateTimeCodecTests {
    @Test func formatsCanonicalDatesWithoutIntermediateFormattingObjects() throws {
        #expect(
            try DatabaseXSDDateTimeCodec.format(
                date: DatabaseDate(year: 2026, month: 7, day: 20)
            ) == "2026-07-20"
        )
        #expect(
            try DatabaseXSDDateTimeCodec.format(
                date: DatabaseDate(year: 10_000, month: 1, day: 2)
            ) == "10000-01-02"
        )
        #expect(
            try DatabaseXSDDateTimeCodec.format(
                date: DatabaseDate(year: 0, month: 2, day: 29)
            ) == "0000-02-29"
        )
    }

    @Test func rejectsInvalidAndNonCanonicalDateLexicalForms() {
        #expect(
            DatabaseXSDDateTimeCodec.parseDate("2024-02-29")
                == DatabaseDate(year: 2024, month: 2, day: 29)
        )
        #expect(DatabaseXSDDateTimeCodec.parseDate("2023-02-29") == nil)
        #expect(DatabaseXSDDateTimeCodec.parseDate("02026-07-20") == nil)
        #expect(DatabaseXSDDateTimeCodec.parseDate("2026-7-20") == nil)
        #expect(DatabaseXSDDateTimeCodec.parseDate("2026-07-20Z") == nil)
    }

    @Test func formatsCanonicalUTCTimestamps() throws {
        #expect(
            try DatabaseXSDDateTimeCodec.format(
                timestamp: DatabaseTimestamp(secondsSinceUnixEpoch: 0)
            ) == "1970-01-01T00:00:00Z"
        )
        #expect(
            try DatabaseXSDDateTimeCodec.format(
                timestamp: DatabaseTimestamp(
                    secondsSinceUnixEpoch: -1,
                    nanoseconds: 120_000_000
                )
            ) == "1969-12-31T23:59:59.12Z"
        )
    }

    @Test func normalizesOffsetsAndEndOfDayWithoutPrecisionLoss() {
        let normalized = DatabaseXSDDateTimeCodec.parseTimestamp(
            "2026-07-20T05:30:00Z"
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T14:30:00+09:00"
            ) == normalized
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T24:00:00Z"
            ) == DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-21T00:00:00Z"
            )
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.1234567890Z"
            ) == DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.123456789Z"
            )
        )
    }

    @Test func rejectsTimestampValuesThatCannotBeRepresentedExactly() {
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T24:00:00.000000001Z"
            ) == nil
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00.1234567891Z"
            ) == nil
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00"
            ) == nil
        )
        #expect(
            DatabaseXSDDateTimeCodec.parseTimestamp(
                "2026-07-20T00:00:00+14:01"
            ) == nil
        )
    }

    @Test func rejectsInvalidValuesAtTheFormattingBoundary() {
        #expect(throws: DatabaseXSDDateTimeError.self) {
            try DatabaseXSDDateTimeCodec.format(
                date: DatabaseDate(year: 2026, month: 2, day: 29)
            )
        }
        #expect(throws: DatabaseXSDDateTimeError.self) {
            try DatabaseXSDDateTimeCodec.format(
                timestamp: DatabaseTimestamp(
                    secondsSinceUnixEpoch: 0,
                    nanoseconds: 1_000_000_000
                )
            )
        }
        #expect(throws: DatabaseXSDDateTimeError.self) {
            try DatabaseXSDDateTimeCodec.format(
                timestamp: DatabaseTimestamp(
                    secondsSinceUnixEpoch: .max
                )
            )
        }
    }
}
