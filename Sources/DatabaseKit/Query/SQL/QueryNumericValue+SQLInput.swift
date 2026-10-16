import DatabaseTypes

extension QueryNumericValue {
    /// Forms a finite SQL numeric value without typmod rounding or runtime policy.
    public init(sqlLexicalForm: borrowing Substring,
                maximumUTF8Count: UInt64) throws(QueryValueError) {
        let count = UInt64(sqlLexicalForm.utf8.count)
        guard count <= maximumUTF8Count else {
            throw .resourceLimit(resource: "numeric input bytes", actual: count, maximum: maximumUTF8Count)
        }
        var input = Input(sqlLexicalForm)
        guard let first = input.current else { throw input.invalid("Empty numeric constant") }
        let negative = first == 45
        if first == 45 || first == 43 { input.advance() }
        guard input.current != nil else { throw input.invalid("Missing numeric digits") }
        if input.current == 48, let prefix = input.next {
            let radix: Int128
            switch prefix {
            case 120, 88: radix = 16
            case 111, 79: radix = 8
            case 98, 66: radix = 2
            default: radix = 0
            }
            if radix != 0 {
                input.advance(); input.advance()
                if input.current == 95 {
                    input.advance()
                    guard let byte = input.current, Self.digit(byte) >= 0, Self.digit(byte) < radix else {
                        throw input.invalid("Invalid radix prefix separator")
                    }
                }
                var value: Int128 = 0
                var seen = false
                var previousDigit = false
                while let byte = input.current {
                    let byteOffset = input.offset
                    input.advance()
                    if byte == 95 {
                        guard previousDigit, let next = input.current,
                              Self.digit(next) >= 0, Self.digit(next) < radix else {
                            throw input.invalid("Invalid numeric digit separator", at: byteOffset)
                        }
                        previousDigit = false
                        continue
                    }
                    let number = Self.digit(byte)
                    guard number >= 0, number < radix else { throw input.invalid("Invalid radix digit", at: byteOffset) }
                    let product = value.multipliedReportingOverflow(by: radix)
                    let sum = product.partialValue.addingReportingOverflow(negative ? -number : number)
                    guard !product.overflow, !sum.overflow else { throw .numericOutOfRange }
                    value = sum.partialValue
                    previousDigit = true
                    seen = true
                }
                guard seen, previousDigit else { throw input.invalid("Missing radix digits") }
                try self.init(value: ExactDecimal(coefficient: value, scale: 0), displayScale: 0)
                return
            }
        }
        var coefficient: Int128 = 0
        var significant = 0
        var pendingZeros: Int64 = 0
        var fractional: Int64 = 0
        var point = false
        var seenDigit = false
        var previousDigit = false
        while let byte = input.current, byte != 101, byte != 69 {
            let byteOffset = input.offset
            input.advance()
            if byte == 46 {
                guard !point else { throw input.invalid("Repeated numeric decimal point", at: byteOffset) }
                point = true
                previousDigit = false
                continue
            }
            if byte == 95 {
                guard previousDigit, let next = input.current, (48...57).contains(next) else {
                    throw input.invalid("Invalid numeric digit separator", at: byteOffset)
                }
                previousDigit = false
                continue
            }
            guard (48...57).contains(byte) else { throw input.invalid("Invalid decimal digit", at: byteOffset) }
            previousDigit = true
            seenDigit = true
            if point { fractional += 1 }
            let number = Int128(byte - 48)
            if number == 0 {
                if coefficient != 0 { pendingZeros += 1 }
                continue
            }
            guard Int64(significant) + pendingZeros + 1 <= 38 else { throw .numericOutOfRange }
            while pendingZeros > 0 { coefficient *= 10; significant += 1; pendingZeros -= 1 }
            coefficient = coefficient * 10 + number
            significant += 1
        }
        guard seenDigit else { throw input.invalid("Missing decimal digits") }
        var exponent: Int64 = 0
        if input.current != nil {
            input.advance()
            guard let first = input.current else { throw input.invalid("Missing exponent digits") }
            let negativeExponent = first == 45
            if first == 45 || first == 43 { input.advance() }
            var seenExponent = false
            previousDigit = false
            while let byte = input.current {
                let byteOffset = input.offset
                input.advance()
                if byte == 95 {
                    guard previousDigit, let next = input.current, (48...57).contains(next) else {
                        throw input.invalid("Invalid exponent separator", at: byteOffset)
                    }
                    previousDigit = false
                    continue
                }
                guard (48...57).contains(byte) else { throw input.invalid("Invalid exponent digit", at: byteOffset) }
                let product = exponent.multipliedReportingOverflow(by: 10)
                let sum = product.partialValue.addingReportingOverflow(Int64(byte - 48))
                guard !product.overflow, !sum.overflow else { throw .numericOutOfRange }
                exponent = sum.partialValue
                seenExponent = true
                previousDigit = true
            }
            guard seenExponent, previousDigit else { throw input.invalid("Missing exponent digits") }
            if negativeExponent { exponent = -exponent }
        }
        let rawScale = fractional.subtractingReportingOverflow(exponent)
        guard !rawScale.overflow, max(0, rawScale.partialValue) <= 16383 else { throw .numericOutOfRange }
        let scale = rawScale.partialValue.subtractingReportingOverflow(pendingZeros)
        guard !scale.overflow, let canonicalScale = Int32(exactly: scale.partialValue),
              coefficient == 0 || Int64(significant) - scale.partialValue <= 131072 else { throw .numericOutOfRange }
        try self.init(value: ExactDecimal(coefficient: negative ? -coefficient : coefficient,
                                         scale: coefficient == 0 ? 0 : canonicalScale),
                      displayScale: Int32(max(0, rawScale.partialValue)))
    }

    private static func digit(_ byte: UInt8) -> Int128 {
        switch byte {
        case 48...57: return Int128(byte - 48)
        case 65...70: return Int128(byte - 65 + 10)
        case 97...102: return Int128(byte - 97 + 10)
        default: return -1
        }
    }

    private struct Input {
        let bytes: Substring.UTF8View
        var index: String.Index
        let end: String.Index
        var offset: UInt64 = 0

        init(_ text: borrowing Substring) {
            bytes = text.utf8
            var first = bytes.startIndex
            var last = bytes.endIndex
            while first != last, Self.isSpace(bytes[first]) {
                bytes.formIndex(after: &first); offset += 1
            }
            while first != last {
                let previous = bytes.index(before: last)
                guard Self.isSpace(bytes[previous]) else { break }
                last = previous
            }
            index = first
            end = last
        }

        var current: UInt8? { index == end ? nil : bytes[index] }
        var next: UInt8? {
            guard index != end else { return nil }
            let next = bytes.index(after: index)
            return next == end ? nil : bytes[next]
        }
        mutating func advance() {
            bytes.formIndex(after: &index); offset += 1
        }
        func invalid(_ reason: String, at byteOffset: UInt64? = nil) -> QueryValueError {
            .invalidNumeric(offset: byteOffset ?? offset, reason: reason)
        }
        private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
    }
}
