import DatabaseTypes
import DatabaseValue

public enum QueryLiteralEncoding {
    public static func iso8601(_ date: CivilDate) -> String {
        "\(formattedYear(Int64(date.year)))-\(padded(Int(date.month), width: 2))-\(padded(Int(date.day), width: 2))"
    }

    public static func iso8601(_ timestamp: Timestamp) -> String {
        var days = timestamp.secondsSinceUnixEpoch / 86_400
        var secondsOfDay = timestamp.secondsSinceUnixEpoch % 86_400
        if secondsOfDay < 0 {
            days -= 1
            secondsOfDay += 86_400
        }

        let date = calendarDateComponents(daysSinceUnixEpoch: days)
        let hour = Int(secondsOfDay / 3_600)
        let minute = Int((secondsOfDay % 3_600) / 60)
        let second = Int(secondsOfDay % 60)
        var result = "\(formattedYear(date.year))-\(padded(Int(date.month), width: 2))-\(padded(Int(date.day), width: 2))T\(padded(hour, width: 2)):\(padded(minute, width: 2)):\(padded(second, width: 2))"

        if timestamp.nanoseconds != 0 {
            var fraction = padded(Int(timestamp.nanoseconds), width: 9)
            while fraction.last == "0" {
                fraction.removeLast()
            }
            result += ".\(fraction)"
        }

        return result + "Z"
    }

    public static func hex(_ bytes: ByteString) -> String {
        let (encodedCount, overflow) = bytes.count.multipliedReportingOverflow(by: 2)
        precondition(!overflow, "Hexadecimal byte count overflow")
        return bytes.withUnsafeBytes { source in
            String(unsafeUninitializedCapacity: encodedCount) { destination in
                var destinationOffset = 0
                for byte in source {
                    destination[destinationOffset] = hexadecimalDigit(byte >> 4)
                    destination[destinationOffset + 1] = hexadecimalDigit(byte & 0x0F)
                    destinationOffset += 2
                }
                return destinationOffset
            }
        }
    }

    public static func base64(_ bytes: ByteString) -> String {
        guard !bytes.isEmpty else { return "" }

        let (roundedCount, roundingOverflow) = bytes.count.addingReportingOverflow(2)
        precondition(!roundingOverflow, "Base64 byte count overflow")
        let (encodedCount, multiplicationOverflow) = (roundedCount / 3)
            .multipliedReportingOverflow(by: 4)
        precondition(!multiplicationOverflow, "Base64 byte count overflow")

        return bytes.withUnsafeBytes { source in
            String(unsafeUninitializedCapacity: encodedCount) { destination in
                var sourceOffset = 0
                var destinationOffset = 0
                while sourceOffset < source.count {
                    let first = UInt32(source[sourceOffset])
                    let hasSecond = sourceOffset + 1 < source.count
                    let hasThird = sourceOffset + 2 < source.count
                    let second = hasSecond ? UInt32(source[sourceOffset + 1]) : 0
                    let third = hasThird ? UInt32(source[sourceOffset + 2]) : 0
                    let value = (first << 16) | (second << 8) | third

                    destination[destinationOffset] = base64Digit(UInt8((value >> 18) & 0x3F))
                    destination[destinationOffset + 1] = base64Digit(UInt8((value >> 12) & 0x3F))
                    destination[destinationOffset + 2] = hasSecond
                        ? base64Digit(UInt8((value >> 6) & 0x3F))
                        : 0x3D
                    destination[destinationOffset + 3] = hasThird
                        ? base64Digit(UInt8(value & 0x3F))
                        : 0x3D
                    sourceOffset += 3
                    destinationOffset += 4
                }
                return destinationOffset
            }
        }
    }

    public static func decimal(_ value: ExactDecimal) -> String {
        let coefficient = value.coefficient
        let scale = value.scale
        guard scale != 0 else { return String(coefficient) }
        let isNegative = coefficient < 0
        let digits = isNegative
            ? String(coefficient).dropFirst()
            : Substring(String(coefficient))
        let sign = isNegative ? "-" : ""

        if scale > 0, scale <= 128 {
            let scale = Int(scale)
            if digits.count > scale {
                let split = digits.index(digits.endIndex, offsetBy: -scale)
                return sign + digits[..<split] + "." + digits[split...]
            }
            return sign + "0." + String(repeating: "0", count: scale - digits.count) + digits
        }

        if scale < 0, scale >= -128 {
            return sign + digits + String(repeating: "0", count: Int(-scale))
        }

        return "\(coefficient)e\(-Int64(scale))"
    }

    private static func calendarDateComponents(
        daysSinceUnixEpoch days: Int64
    ) -> (year: Int64, month: UInt8, day: UInt8) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        var year = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthPrime = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthPrime + 2) / 5 + 1
        let month = monthPrime + (monthPrime < 10 ? 3 : -9)
        if month <= 2 { year += 1 }
        return (year, UInt8(month), UInt8(day))
    }

    private static func formattedYear(_ year: Int64) -> String {
        if year >= 0 {
            return padded(year, width: 4)
        }
        return "-" + padded(year.magnitude, width: 4)
    }

    private static func padded<T: BinaryInteger>(
        _ value: T,
        width: Int
    ) -> String {
        let raw = String(value)
        guard raw.count < width else { return raw }
        return String(repeating: "0", count: width - raw.count) + raw
    }

    private static func hexadecimalDigit(_ value: UInt8) -> UInt8 {
        value < 10 ? 48 + value : 55 + value
    }

    private static func base64Digit(_ value: UInt8) -> UInt8 {
        switch value {
        case 0..<26:
            return 65 + value
        case 26..<52:
            return 71 + value
        case 52..<62:
            return value - 4
        case 62:
            return 43
        default:
            return 47
        }
    }
}
