import DatabaseTypes

extension QueryJSONParser {
    mutating func readString() throws(QueryValueError) -> String {
        offset += 1
        var result = ""
        while let byte = peek {
            if byte == 34 { offset += 1; return result }
            guard byte >= 32 else { throw invalid("Unescaped control character") }
            if byte != 92 {
                let start = offset
                while let current = peek, current >= 32, current != 34, current != 92 { offset += 1 }
                if buildsTree {
                    try admitDecodedBytes(UInt64(offset - start))
                    // Decoding is required at the JSONB string ownership boundary.
                    result += String(decoding: input[start..<offset], as: UTF8.self)
                }
                continue
            }
            offset += 1
            guard let escape = peek else { throw invalid("Incomplete string escape") }
            offset += 1
            let scalar: UInt32
            switch escape {
            case 34, 47, 92: scalar = UInt32(escape)
            case 98: scalar = 8
            case 102: scalar = 12
            case 110: scalar = 10
            case 114: scalar = 13
            case 116: scalar = 9
            case 117:
                let first = try readHexQuad()
                guard buildsTree else { continue }
                if (0xD800...0xDBFF).contains(first) {
                    guard consume(92), consume(117) else { throw invalid("Unpaired high surrogate") }
                    let second = try readHexQuad()
                    guard (0xDC00...0xDFFF).contains(second) else { throw invalid("Invalid surrogate pair") }
                    scalar = 0x10000 + ((first - 0xD800) << 10) + second - 0xDC00
                } else {
                    guard !(0xDC00...0xDFFF).contains(first) else { throw invalid("Unpaired low surrogate") }
                    scalar = first
                }
                guard scalar != 0 else { throw invalid("JSONB cannot contain U+0000") }
            default: throw invalid("Invalid string escape")
            }
            if buildsTree {
                let byteCount: UInt64 = scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4
                try admitDecodedBytes(byteCount)
                guard let unicode = Unicode.Scalar(scalar) else { throw invalid("Invalid Unicode scalar") }
                result.unicodeScalars.append(unicode)
            }
        }
        throw invalid("Unterminated string")
    }

    mutating func admitDecodedBytes(_ count: UInt64) throws(QueryValueError) {
        let next = decodedBytes.addingReportingOverflow(count)
        guard !next.overflow else { throw .arithmeticOverflow }
        try Self.check(next.partialValue, maximum: limits.maximumRetainedBytes, resource: "retainedBytes")
        decodedBytes = next.partialValue
    }

    mutating func readHexQuad() throws(QueryValueError) -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = peek else { throw invalid("Incomplete Unicode escape") }
            let digit: UInt32
            switch byte {
            case 48...57: digit = UInt32(byte - 48)
            case 65...70: digit = UInt32(byte - 65 + 10)
            case 97...102: digit = UInt32(byte - 97 + 10)
            default: throw invalid("Invalid Unicode escape")
            }
            result = result * 16 + digit
            offset += 1
        }
        return result
    }

    mutating func readNumber() throws(QueryValueError) -> QueryNumericValue? {
        let start = offset
        _ = consume(45)
        if !consume(48) {
            guard let first = peek, (49...57).contains(first) else { throw invalid("Invalid number integer part") }
            while let digit = peek, (48...57).contains(digit) { offset += 1 }
        }
        if consume(46) {
            let fractionStart = offset
            while let digit = peek, (48...57).contains(digit) { offset += 1 }
            guard offset > fractionStart else { throw invalid("Missing fraction digits") }
        }
        if consume(101) || consume(69) {
            if !consume(43) { _ = consume(45) }
            let exponentStart = offset
            while let digit = peek, (48...57).contains(digit) { offset += 1 }
            guard offset > exponentStart else { throw invalid("Missing exponent digits") }
        }
        guard buildsTree else { return nil }
        return try decodeNumber(start: start, end: offset)
    }

    func decodeNumber(start: Int, end: Int) throws(QueryValueError) -> QueryNumericValue {
        var index = start
        let negative = input[index] == 45
        if negative { index += 1 }
        var coefficient: Int128 = 0
        var significantDigits = 0
        var pendingZeros: Int64 = 0
        var fractionDigits: Int64 = 0
        var afterPoint = false
        while index < end, input[index] != 101, input[index] != 69 {
            let byte = input[index]
            index += 1
            if byte == 46 { afterPoint = true; continue }
            if afterPoint { fractionDigits += 1 }
            let digit = Int128(byte - 48)
            if digit == 0 {
                if coefficient != 0 { pendingZeros += 1 }
                continue
            }
            guard Int64(significantDigits) + pendingZeros + 1 <= 38 else { throw .numericOutOfRange }
            while pendingZeros > 0 { coefficient *= 10; significantDigits += 1; pendingZeros -= 1 }
            coefficient = coefficient * 10 + digit
            significantDigits += 1
        }
        var exponent: Int64 = 0
        if index < end {
            index += 1
            let negativeExponent = input[index] == 45
            if input[index] == 45 || input[index] == 43 { index += 1 }
            while index < end {
                let product = exponent.multipliedReportingOverflow(by: 10)
                let sum = product.partialValue.addingReportingOverflow(Int64(input[index] - 48))
                guard !product.overflow, !sum.overflow else { throw .numericOutOfRange }
                exponent = sum.partialValue
                index += 1
            }
            if negativeExponent { exponent = -exponent }
        }
        let rawScale = fractionDigits.subtractingReportingOverflow(exponent)
        guard !rawScale.overflow else { throw .numericOutOfRange }
        let displayScale = max(0, rawScale.partialValue)
        guard displayScale <= 16383 else { throw .numericOutOfRange }
        let canonicalScale = rawScale.partialValue.subtractingReportingOverflow(pendingZeros)
        guard !canonicalScale.overflow,
              coefficient == 0 || Int32(exactly: canonicalScale.partialValue) != nil else { throw .numericOutOfRange }
        return try QueryNumericValue(
            value: ExactDecimal(coefficient: negative ? -coefficient : coefficient, scale: coefficient == 0 ? 0 : Int32(canonicalScale.partialValue)),
            displayScale: Int32(displayScale)
        )
    }
}
