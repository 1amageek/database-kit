public struct DatabaseExactDecimal: Sendable, Hashable {
    public let coefficient: Int64
    public let scale: Int32

    public init(coefficient: Int64, scale: Int32) {
        var coefficient = coefficient
        var scale = scale
        while coefficient != 0, coefficient % 10 == 0, scale > Int32.min {
            coefficient /= 10
            scale -= 1
        }
        if coefficient == 0 {
            self.coefficient = 0
            self.scale = 0
        } else {
            self.coefficient = coefficient
            self.scale = scale
        }
    }

    public init?(_ value: FieldValue) {
        switch value {
        case .int8(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .int16(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .int32(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .int64(let coefficient):
            self.init(coefficient: coefficient, scale: 0)
        case .uint8(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .uint16(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .uint32(let coefficient):
            self.init(coefficient: Int64(coefficient), scale: 0)
        case .uint64(let coefficient):
            guard let signed = Int64(exactly: coefficient) else { return nil }
            self.init(coefficient: signed, scale: 0)
        case .decimal(let coefficient, let scale):
            self.init(coefficient: coefficient, scale: scale)
        default:
            return nil
        }
    }

    public var fieldValue: FieldValue {
        .decimal(coefficient: coefficient, scale: scale)
    }

    public func adding(
        _ other: Self
    ) throws(DatabaseExactDecimalError) -> Self {
        if coefficient == 0 { return other }
        if other.coefficient == 0 { return self }
        let aligned = try aligned(with: other)
        let result = aligned.left.addingReportingOverflow(aligned.right)
        guard !result.overflow else { throw .numericOverflow }
        return try Self.normalized(
            coefficient: result.partialValue,
            scale: aligned.scale
        )
    }

    public func subtracting(
        _ other: Self
    ) throws(DatabaseExactDecimalError) -> Self {
        if other.coefficient == 0 { return self }
        if coefficient == 0 { return try other.negated() }
        let aligned = try aligned(with: other)
        let result = aligned.left.subtractingReportingOverflow(aligned.right)
        guard !result.overflow else { throw .numericOverflow }
        return try Self.normalized(
            coefficient: result.partialValue,
            scale: aligned.scale
        )
    }

    public func multiplying(
        by other: Self
    ) throws(DatabaseExactDecimalError) -> Self {
        if coefficient == 0 || other.coefficient == 0 {
            return Self(coefficient: 0, scale: 0)
        }
        let scale = scale.addingReportingOverflow(other.scale)
        guard !scale.overflow else {
            throw .numericOverflow
        }
        return try Self.normalized(
            coefficient: Int128(coefficient) * Int128(other.coefficient),
            scale: scale.partialValue
        )
    }

    public func dividing(
        by other: Self
    ) throws(DatabaseExactDecimalError) -> Self {
        guard other.coefficient != 0 else { throw .divisionByZero }
        guard coefficient != 0 else { return Self(coefficient: 0, scale: 0) }

        var numerator = coefficient.magnitude
        var denominator = other.coefficient.magnitude
        let divisor = Self.greatestCommonDivisor(numerator, denominator)
        numerator /= divisor
        denominator /= divisor

        var powersOfTwo: Int32 = 0
        while denominator.isMultiple(of: 2) {
            denominator /= 2
            powersOfTwo += 1
        }
        var powersOfFive: Int32 = 0
        while denominator.isMultiple(of: 5) {
            denominator /= 5
            powersOfFive += 1
        }
        guard denominator == 1 else { throw .inexactResult }

        let decimalPlaces = max(powersOfTwo, powersOfFive)
        let isNegative = (coefficient < 0) != (other.coefficient < 0)
        let maximumMagnitude = isNegative
            ? UInt64(Int64.max) + 1
            : UInt64(Int64.max)

        for _ in powersOfTwo..<decimalPlaces {
            guard numerator <= maximumMagnitude / 2 else {
                throw .numericOverflow
            }
            numerator *= 2
        }
        for _ in powersOfFive..<decimalPlaces {
            guard numerator <= maximumMagnitude / 5 else {
                throw .numericOverflow
            }
            numerator *= 5
        }

        let coefficient: Int64
        if isNegative {
            if numerator == UInt64(Int64.max) + 1 {
                coefficient = Int64.min
            } else {
                guard let signed = Int64(exactly: numerator) else {
                    throw .numericOverflow
                }
                coefficient = -signed
            }
        } else {
            guard let signed = Int64(exactly: numerator) else {
                throw .numericOverflow
            }
            coefficient = signed
        }

        let scaleDifference = scale.subtractingReportingOverflow(other.scale)
        guard !scaleDifference.overflow else { throw .numericOverflow }
        let resultScale = scaleDifference.partialValue.addingReportingOverflow(
            decimalPlaces
        )
        guard !resultScale.overflow else { throw .numericOverflow }
        return Self(
            coefficient: coefficient,
            scale: resultScale.partialValue
        )
    }

    public func remainder(
        dividingBy other: Self
    ) throws(DatabaseExactDecimalError) -> Self {
        guard other.coefficient != 0 else { throw .divisionByZero }
        guard coefficient != 0 else { return self }

        let magnitudeComparison = compareMagnitude(to: other)
        if magnitudeComparison < 0 { return self }
        if magnitudeComparison == 0 {
            return Self(coefficient: 0, scale: 0)
        }

        let targetScale = max(scale, other.scale)
        let leftPower = targetScale.subtractingReportingOverflow(scale)
        let rightPower = targetScale.subtractingReportingOverflow(other.scale)
        guard !leftPower.overflow, !rightPower.overflow else {
            throw .numericOverflow
        }

        let modulus = try Self.scaledMagnitude(
            other.coefficient.magnitude,
            by: rightPower.partialValue,
            maximum: UInt64(Int64.max) + 1
        )
        guard modulus != 0 else { throw .divisionByZero }
        let remainderMagnitude = Self.modularScale(
            coefficient.magnitude,
            by: leftPower.partialValue,
            modulus: modulus
        )
        let remainder: Int64
        if coefficient < 0 {
            if remainderMagnitude == UInt64(Int64.max) + 1 {
                remainder = Int64.min
            } else {
                guard let signed = Int64(exactly: remainderMagnitude) else {
                    throw .numericOverflow
                }
                remainder = -signed
            }
        } else {
            guard let signed = Int64(exactly: remainderMagnitude) else {
                throw .numericOverflow
            }
            remainder = signed
        }
        return Self(
            coefficient: remainder,
            scale: targetScale
        )
    }

    public func negated() throws(DatabaseExactDecimalError) -> Self {
        guard coefficient != Int64.min else { throw .numericOverflow }
        return Self(coefficient: -coefficient, scale: scale)
    }

    public func magnitude() throws(DatabaseExactDecimalError) -> Self {
        coefficient < 0 ? try negated() : self
    }

    public func compare(to other: Self) -> Int {
        if coefficient == other.coefficient, scale == other.scale { return 0 }
        if coefficient < 0, other.coefficient >= 0 { return -1 }
        if coefficient >= 0, other.coefficient < 0 { return 1 }
        let magnitudeComparison = compareMagnitude(to: other)
        return coefficient < 0 ? -magnitudeComparison : magnitudeComparison
    }

    public func decimalLexicalForm(
        maximumUTF8Count: Int
    ) throws(DatabaseExactDecimalLexicalError) -> String {
        guard maximumUTF8Count >= 0 else {
            throw .invalidMaximumUTF8Count(maximumUTF8Count)
        }

        let digits = Array(String(coefficient.magnitude).utf8)
        let signCount = coefficient < 0 ? 1 : 0
        let requiredCount: UInt64
        let fractionalZeroCount: Int
        let integralZeroCount: Int
        let decimalPointOffset: Int?

        if scale <= 0 {
            integralZeroCount = Int(-Int64(scale))
            fractionalZeroCount = 0
            decimalPointOffset = nil
            requiredCount = UInt64(signCount + digits.count + integralZeroCount)
        } else if digits.count > Int(scale) {
            integralZeroCount = 0
            fractionalZeroCount = 0
            decimalPointOffset = digits.count - Int(scale)
            requiredCount = UInt64(signCount + digits.count + 1)
        } else {
            integralZeroCount = 0
            fractionalZeroCount = Int(scale) - digits.count
            decimalPointOffset = 0
            requiredCount = UInt64(
                signCount + 2 + fractionalZeroCount + digits.count
            )
        }

        let maximum = UInt64(maximumUTF8Count)
        guard requiredCount <= maximum else {
            throw .representationTooLarge(
                required: requiredCount,
                maximum: maximum
            )
        }
        let capacity = Int(requiredCount)
        return String(unsafeUninitializedCapacity: capacity) { destination in
            var offset = 0
            if coefficient < 0 {
                destination[offset] = 0x2D
                offset += 1
            }

            if decimalPointOffset == 0 {
                destination[offset] = 0x30
                destination[offset + 1] = 0x2E
                offset += 2
                for _ in 0..<fractionalZeroCount {
                    destination[offset] = 0x30
                    offset += 1
                }
                for digit in digits {
                    destination[offset] = digit
                    offset += 1
                }
                return offset
            }

            for (index, digit) in digits.enumerated() {
                if decimalPointOffset == index {
                    destination[offset] = 0x2E
                    offset += 1
                }
                destination[offset] = digit
                offset += 1
            }
            for _ in 0..<integralZeroCount {
                destination[offset] = 0x30
                offset += 1
            }
            return offset
        }
    }

    private func aligned(
        with other: Self
    ) throws(DatabaseExactDecimalError) -> (
        left: Int128,
        right: Int128,
        scale: Int32
    ) {
        let targetScale = max(scale, other.scale)
        let leftPower = targetScale.subtractingReportingOverflow(scale)
        let rightPower = targetScale.subtractingReportingOverflow(other.scale)
        guard !leftPower.overflow, !rightPower.overflow else {
            throw .numericOverflow
        }
        return (
            try Self.scaled(Int128(coefficient), by: leftPower.partialValue),
            try Self.scaled(Int128(other.coefficient), by: rightPower.partialValue),
            targetScale
        )
    }

    private static func scaled(
        _ value: Int128,
        by power: Int32
    ) throws(DatabaseExactDecimalError) -> Int128 {
        guard power >= 0 else { throw .numericOverflow }
        if value == 0 { return 0 }
        var result = value
        for _ in 0..<power {
            let expanded = result.multipliedReportingOverflow(by: 10)
            guard !expanded.overflow else { throw .numericOverflow }
            result = expanded.partialValue
        }
        return result
    }

    private static func normalized(
        coefficient: Int128,
        scale: Int32
    ) throws(DatabaseExactDecimalError) -> Self {
        var coefficient = coefficient
        var scale = scale
        while coefficient != 0,
              coefficient.isMultiple(of: 10),
              scale > Int32.min {
            coefficient /= 10
            scale -= 1
        }
        guard let exact = Int64(exactly: coefficient) else {
            throw .numericOverflow
        }
        return Self(coefficient: exact, scale: scale)
    }

    private func compareMagnitude(to other: Self) -> Int {
        let leftDigits = Array(String(coefficient.magnitude).utf8)
        let rightDigits = Array(String(other.coefficient.magnitude).utf8)
        let leftLeadingPower = Int64(leftDigits.count - 1) - Int64(scale)
        let rightLeadingPower = Int64(rightDigits.count - 1) - Int64(other.scale)
        if leftLeadingPower != rightLeadingPower {
            return leftLeadingPower < rightLeadingPower ? -1 : 1
        }

        let count = max(leftDigits.count, rightDigits.count)
        for index in 0..<count {
            let left = index < leftDigits.count ? leftDigits[index] : 0x30
            let right = index < rightDigits.count ? rightDigits[index] : 0x30
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }

    private static func greatestCommonDivisor(
        _ left: UInt64,
        _ right: UInt64
    ) -> UInt64 {
        var left = left
        var right = right
        while right != 0 {
            let remainder = left % right
            left = right
            right = remainder
        }
        return left
    }

    private static func scaledMagnitude(
        _ value: UInt64,
        by power: Int32,
        maximum: UInt64
    ) throws(DatabaseExactDecimalError) -> UInt64 {
        guard power >= 0 else { throw .numericOverflow }
        var result = value
        for _ in 0..<power {
            guard result <= maximum / 10 else { throw .numericOverflow }
            result *= 10
        }
        return result
    }

    private static func modularScale(
        _ value: UInt64,
        by power: Int32,
        modulus: UInt64
    ) -> UInt64 {
        guard modulus != 1 else { return 0 }
        var result = value % modulus
        var factor = UInt64(10) % modulus
        var exponent = UInt32(power)
        while exponent > 0 {
            if !exponent.isMultiple(of: 2) {
                result = UInt64(
                    (UInt128(result) * UInt128(factor)) % UInt128(modulus)
                )
            }
            exponent /= 2
            if exponent > 0 {
                factor = UInt64(
                    (UInt128(factor) * UInt128(factor)) % UInt128(modulus)
                )
            }
        }
        return result
    }
}
