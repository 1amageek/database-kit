import DatabaseTypes

/// Formats and parses canonical XSD date and dateTime values without Foundation.
public enum XSDDateTimeCodec {
    public static func format(date: CivilDate) -> String {
        return formatDateUnchecked(date)
    }

    public static func parseDate(_ value: String) -> CivilDate? {
        var scanner = XSDDateTimeScanner(value)
        guard let date = scanner.readDate(), scanner.isAtEnd else {
            return nil
        }
        return date
    }

    public static func format(
        timestamp: Timestamp
    ) throws(XSDDateTimeError) -> String {
        let (days, secondOfDay) = splitUnixSeconds(
            timestamp.secondsSinceUnixEpoch
        )
        let civil = civilDate(fromDaysSinceUnixEpoch: days)
        guard let year = Int32(exactly: civil.year) else {
            throw XSDDateTimeError.timestampOutOfSupportedYearRange
        }
        let date: CivilDate
        do {
            date = try CivilDate(
                year: year,
                month: UInt8(civil.month),
                day: UInt8(civil.day)
            )
        } catch {
            preconditionFailure(
                "Unix timestamp conversion produced an invalid civil date"
            )
        }
        let hour = UInt8(secondOfDay / 3_600)
        let minute = UInt8((secondOfDay % 3_600) / 60)
        let second = UInt8(secondOfDay % 60)
        let fractionDigits = significantFractionDigits(timestamp.nanoseconds)
        let dateByteCount = formattedDateByteCount(date)
        let byteCount = dateByteCount + 10
            + (fractionDigits == 0 ? 0 : 1 + fractionDigits)

        return String(unsafeUninitializedCapacity: byteCount) { output in
            var offset = 0
            writeDate(date, to: output, offset: &offset)
            output[offset] = 84
            offset += 1
            writeUnsigned(UInt64(hour), width: 2, to: output, offset: &offset)
            output[offset] = 58
            offset += 1
            writeUnsigned(UInt64(minute), width: 2, to: output, offset: &offset)
            output[offset] = 58
            offset += 1
            writeUnsigned(UInt64(second), width: 2, to: output, offset: &offset)
            if fractionDigits > 0 {
                output[offset] = 46
                offset += 1
                let divisor = powerOfTen(9 - fractionDigits)
                writeUnsigned(
                    UInt64(timestamp.nanoseconds) / divisor,
                    width: fractionDigits,
                    to: output,
                    offset: &offset
                )
            }
            output[offset] = 90
            offset += 1
            return offset
        }
    }

    public static func parseTimestamp(
        _ value: String
    ) -> Timestamp? {
        var scanner = XSDDateTimeScanner(value)
        guard let date = scanner.readDate(),
              scanner.read(84),
              let hour = scanner.readFixedUnsigned(count: 2),
              scanner.read(58),
              let minute = scanner.readFixedUnsigned(count: 2),
              scanner.read(58),
              let second = scanner.readFixedUnsigned(count: 2),
              hour <= 24,
              minute <= 59,
              second <= 59 else {
            return nil
        }

        var nanoseconds: UInt32 = 0
        if scanner.readIfPresent(46) {
            guard let fraction = scanner.readFractionNanoseconds() else {
                return nil
            }
            nanoseconds = fraction
        }
        guard hour < 24
                || (minute == 0 && second == 0 && nanoseconds == 0) else {
            return nil
        }

        let offsetSeconds: Int64
        if scanner.readIfPresent(90) {
            offsetSeconds = 0
        } else {
            let sign: Int64
            if scanner.readIfPresent(43) {
                sign = 1
            } else if scanner.readIfPresent(45) {
                sign = -1
            } else {
                return nil
            }
            guard let offsetHour = scanner.readFixedUnsigned(count: 2),
                  scanner.read(58),
                  let offsetMinute = scanner.readFixedUnsigned(count: 2),
                  offsetHour <= 14,
                  offsetMinute <= 59,
                  offsetHour < 14 || offsetMinute == 0 else {
                return nil
            }
            offsetSeconds = sign * Int64(offsetHour * 3_600 + offsetMinute * 60)
        }
        guard scanner.isAtEnd,
              let days = daysSinceUnixEpoch(date),
              let daySeconds = multipliedWithoutOverflow(days, by: 86_400),
              let localSeconds = addedWithoutOverflow(
                daySeconds,
                Int64(hour * 3_600 + minute * 60 + second)
              ),
              let utcSeconds = subtractedWithoutOverflow(
                localSeconds,
                offsetSeconds
              ) else {
            return nil
        }
        do {
            return try Timestamp(
                secondsSinceUnixEpoch: utcSeconds,
                nanoseconds: nanoseconds
            )
        } catch {
            return nil
        }
    }

    private static func formatDateUnchecked(_ date: CivilDate) -> String {
        let byteCount = formattedDateByteCount(date)
        return String(unsafeUninitializedCapacity: byteCount) { output in
            var offset = 0
            writeDate(date, to: output, offset: &offset)
            return offset
        }
    }

    private static func formattedDateByteCount(_ date: CivilDate) -> Int {
        let magnitude = date.year < 0
            ? UInt64(-Int64(date.year))
            : UInt64(date.year)
        return (date.year < 0 ? 1 : 0)
            + max(4, decimalDigitCount(magnitude))
            + 6
    }

    private static func writeDate(
        _ date: CivilDate,
        to output: UnsafeMutableBufferPointer<UInt8>,
        offset: inout Int
    ) {
        let magnitude: UInt64
        if date.year < 0 {
            output[offset] = 45
            offset += 1
            magnitude = UInt64(-Int64(date.year))
        } else {
            magnitude = UInt64(date.year)
        }
        writeUnsigned(
            magnitude,
            width: max(4, decimalDigitCount(magnitude)),
            to: output,
            offset: &offset
        )
        output[offset] = 45
        offset += 1
        writeUnsigned(UInt64(date.month), width: 2, to: output, offset: &offset)
        output[offset] = 45
        offset += 1
        writeUnsigned(UInt64(date.day), width: 2, to: output, offset: &offset)
    }

    private static func writeUnsigned(
        _ value: UInt64,
        width: Int,
        to output: UnsafeMutableBufferPointer<UInt8>,
        offset: inout Int
    ) {
        var divisor = powerOfTen(width - 1)
        for _ in 0..<width {
            output[offset] = 48 + UInt8((value / divisor) % 10)
            offset += 1
            divisor = divisor == 1 ? 1 : divisor / 10
        }
    }

    private static func decimalDigitCount(_ value: UInt64) -> Int {
        var remaining = value
        var count = 1
        while remaining >= 10 {
            remaining /= 10
            count += 1
        }
        return count
    }

    private static func significantFractionDigits(_ value: UInt32) -> Int {
        guard value != 0 else { return 0 }
        var remaining = value
        var trailingZeroCount = 0
        while remaining.isMultiple(of: 10) {
            remaining /= 10
            trailingZeroCount += 1
        }
        return 9 - trailingZeroCount
    }

    private static func powerOfTen(_ exponent: Int) -> UInt64 {
        var value: UInt64 = 1
        if exponent > 0 {
            for _ in 0..<exponent {
                value *= 10
            }
        }
        return value
    }

    private static func splitUnixSeconds(_ seconds: Int64) -> (Int64, Int64) {
        var days = seconds / 86_400
        var secondOfDay = seconds % 86_400
        if secondOfDay < 0 {
            days -= 1
            secondOfDay += 86_400
        }
        return (days, secondOfDay)
    }

    private static func civilDate(
        fromDaysSinceUnixEpoch days: Int64
    ) -> (year: Int64, month: Int64, day: Int64) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (
            dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524
                - dayOfEra / 146_096
        ) / 365
        var year = yearOfEra + era * 400
        let dayOfYear = dayOfEra
            - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        year += month <= 2 ? 1 : 0
        return (year, month, day)
    }

    private static func daysSinceUnixEpoch(_ date: CivilDate) -> Int64? {
        let year = Int64(date.year)
        let month = Int64(date.month)
        let day = Int64(date.day)
        let adjustedYear = year - (month <= 2 ? 1 : 0)
        let era = (adjustedYear >= 0 ? adjustedYear : adjustedYear - 399) / 400
        let yearOfEra = adjustedYear - era * 400
        let adjustedMonth = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * adjustedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4
            - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func daysInMonth(year: Int64, month: Int64) -> Int64 {
        switch month {
        case 2:
            let leap = year.isMultiple(of: 4)
                && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
            return leap ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func multipliedWithoutOverflow(
        _ lhs: Int64,
        by rhs: Int64
    ) -> Int64? {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func addedWithoutOverflow(
        _ lhs: Int64,
        _ rhs: Int64
    ) -> Int64? {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }

    private static func subtractedWithoutOverflow(
        _ lhs: Int64,
        _ rhs: Int64
    ) -> Int64? {
        let result = lhs.subtractingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}

private struct XSDDateTimeScanner {
    private let bytes: String.UTF8View
    private var index: String.UTF8View.Index

    init(_ value: String) {
        self.bytes = value.utf8
        self.index = bytes.startIndex
    }

    var isAtEnd: Bool { index == bytes.endIndex }

    mutating func read(_ expected: UInt8) -> Bool {
        guard index != bytes.endIndex, bytes[index] == expected else {
            return false
        }
        bytes.formIndex(after: &index)
        return true
    }

    mutating func readIfPresent(_ expected: UInt8) -> Bool {
        read(expected)
    }

    mutating func readDate() -> CivilDate? {
        let negative = readIfPresent(45)
        var yearMagnitude: UInt64 = 0
        var yearDigitCount = 0
        var firstYearDigit: UInt8?
        let maximumMagnitude = UInt64(Int32.max) + 1
        while index != bytes.endIndex, bytes[index] != 45 {
            let byte = bytes[index]
            guard (48...57).contains(byte) else {
                return nil
            }
            if firstYearDigit == nil {
                firstYearDigit = byte
            }
            let digit = UInt64(byte - 48)
            guard yearMagnitude <= (maximumMagnitude - digit) / 10 else {
                return nil
            }
            yearMagnitude = yearMagnitude * 10 + digit
            yearDigitCount += 1
            bytes.formIndex(after: &index)
        }
        guard yearDigitCount >= 4,
              yearDigitCount == 4 || firstYearDigit != 48,
              read(45),
              let month = readFixedUnsigned(count: 2),
              read(45),
              let day = readFixedUnsigned(count: 2) else {
            return nil
        }
        let signedYear: Int64
        if negative {
            guard yearMagnitude <= UInt64(Int32.max) + 1 else { return nil }
            signedYear = -Int64(yearMagnitude)
        } else {
            guard yearMagnitude <= UInt64(Int32.max) else { return nil }
            signedYear = Int64(yearMagnitude)
        }
        do {
            return try CivilDate(
                year: Int32(signedYear),
                month: UInt8(month),
                day: UInt8(day)
            )
        } catch {
            return nil
        }
    }

    mutating func readFixedUnsigned(count: Int) -> UInt64? {
        var value: UInt64 = 0
        for _ in 0..<count {
            guard index != bytes.endIndex else { return nil }
            let byte = bytes[index]
            guard (48...57).contains(byte) else { return nil }
            value = value * 10 + UInt64(byte - 48)
            bytes.formIndex(after: &index)
        }
        return value
    }

    mutating func readFractionNanoseconds() -> UInt32? {
        var value: UInt32 = 0
        var count = 0
        while index != bytes.endIndex {
            let byte = bytes[index]
            guard (48...57).contains(byte) else { break }
            if count < 9 {
                value = value * 10 + UInt32(byte - 48)
            } else if byte != 48 {
                return nil
            }
            count += 1
            bytes.formIndex(after: &index)
        }
        guard count > 0 else { return nil }
        if count < 9 {
            for _ in count..<9 {
                value *= 10
            }
        }
        return value
    }
}
