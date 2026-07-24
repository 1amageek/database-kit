import DatabaseTypes

extension Literal {
    public static func parseInteger(_ lexicalForm: String) -> Literal? {
        if let value = Int64(lexicalForm) {
            return .int(value)
        }
        guard lexicalForm.first != "-", let value = UInt64(lexicalForm) else {
            return nil
        }
        return .uint(value)
    }

    public static func parseDecimal(_ lexicalForm: String) -> Literal? {
        guard !lexicalForm.isEmpty else { return nil }

        let exponentSplit = lexicalForm.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "e" || $0 == "E" }
        )
        guard exponentSplit.count <= 2 else { return nil }
        let mantissa = exponentSplit[0]
        let exponent: Int64
        if exponentSplit.count == 2 {
            guard !exponentSplit[1].isEmpty, let parsed = Int64(exponentSplit[1]) else {
                return nil
            }
            exponent = parsed
        } else {
            exponent = 0
        }

        var body = mantissa[...]
        var isNegative = false
        if body.first == "-" || body.first == "+" {
            isNegative = body.first == "-"
            body = body.dropFirst()
        }
        guard !body.isEmpty else { return nil }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : Substring()
        guard (!whole.isEmpty || !fraction.isEmpty),
              whole.allSatisfy({ $0.isNumber }),
              fraction.allSatisfy({ $0.isNumber }) else {
            return nil
        }

        var digits = String(whole) + String(fraction)
        while digits.first == "0" { digits.removeFirst() }
        if digits.isEmpty {
            return .decimal(ExactDecimal(coefficient: 0, scale: 0))
        }

        var scale = Int64(fraction.count)
        while scale > 0, digits.last == "0" {
            digits.removeLast()
            scale -= 1
        }
        guard let adjustedScale = Int32(exactly: scale - exponent) else {
            return nil
        }

        let signedDigits = isNegative ? "-" + digits : digits
        guard let coefficient = Int128(signedDigits) else { return nil }
        return .decimal(
            ExactDecimal(coefficient: coefficient, scale: adjustedScale)
        )
    }

    public func compareExactNumeric(to other: Literal) -> Int? {
        guard let left = ExactNumericMagnitude(self),
              let right = ExactNumericMagnitude(other) else {
            return nil
        }
        return left.compare(to: right)
    }
}

private struct ExactNumericMagnitude {
    private let isNegative: Bool
    private let digits: [UInt8]
    private let leadingPower: Int64

    init?(_ literal: Literal) {
        let lexicalDigits: String
        let scale: Int64
        switch literal {
        case .int(let value):
            lexicalDigits = String(value)
            scale = 0
        case .uint(let value):
            lexicalDigits = String(value)
            scale = 0
        case .decimal(let value):
            lexicalDigits = String(value.coefficient)
            scale = Int64(value.scale)
        default:
            return nil
        }

        let negative = lexicalDigits.first == "-"
        let magnitude = negative ? lexicalDigits.dropFirst() : Substring(lexicalDigits)
        let normalized = magnitude.drop(while: { $0 == "0" })
        if normalized.isEmpty {
            isNegative = false
            digits = [0]
            leadingPower = 0
            return
        }
        isNegative = negative
        digits = normalized.utf8.map { $0 - 48 }
        leadingPower = Int64(digits.count - 1) - scale
    }

    func compare(to other: Self) -> Int {
        if digits == [0], other.digits == [0] { return 0 }
        if isNegative != other.isNegative { return isNegative ? -1 : 1 }

        let magnitudeComparison: Int
        if leadingPower != other.leadingPower {
            magnitudeComparison = leadingPower < other.leadingPower ? -1 : 1
        } else {
            magnitudeComparison = compareDigits(to: other)
        }
        return isNegative ? -magnitudeComparison : magnitudeComparison
    }

    private func compareDigits(to other: Self) -> Int {
        let count = max(digits.count, other.digits.count)
        for index in 0..<count {
            let left = index < digits.count ? digits[index] : 0
            let right = index < other.digits.count ? other.digits[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}
