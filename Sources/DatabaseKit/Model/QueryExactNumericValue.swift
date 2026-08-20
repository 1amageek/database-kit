import DatabaseTypes

/// Exact finite numeric form used only for query comparison.
/// Digits contain the normalized unsigned decimal coefficient and `scale`
/// retains the `ExactDecimal` meaning: coefficient × 10⁻ˢᶜᵃˡᵉ.
struct QueryExactNumericValue {
    let isNegative: Bool
    let digits: [UInt8]
    let scale: Int64

    init?(_ value: FieldValue) {
        switch value {
        case .int8(let value): self.init(Int128(value))
        case .int16(let value): self.init(Int128(value))
        case .int32(let value): self.init(Int128(value))
        case .int64(let value): self.init(Int128(value))
        case .uint8(let value): self.init(UInt128(value))
        case .uint16(let value): self.init(UInt128(value))
        case .uint32(let value): self.init(UInt128(value))
        case .uint64(let value): self.init(UInt128(value))
        case .float32(let value):
            guard value.isFinite else { return nil }
            self.init(Double(value))
        case .float64(let value):
            guard value.isFinite else { return nil }
            self.init(value)
        case .decimal(let value):
            self.init(value)
        default:
            return nil
        }
    }

    init(_ value: Double) {
        let bits = value.bitPattern
        let negative = bits >> 63 != 0
        let exponentBits = Int((bits >> 52) & 0x7FF)
        let fraction = bits & 0x000F_FFFF_FFFF_FFFF
        if exponentBits == 0, fraction == 0 {
            self.init(isNegative: false, digits: [0], scale: 0)
            return
        }

        var significand = exponentBits == 0
            ? fraction
            : fraction | (UInt64(1) << 52)
        var binaryExponent = exponentBits == 0
            ? 1 - 1023 - 52
            : exponentBits - 1023 - 52
        while binaryExponent < 0, significand.isMultiple(of: 2) {
            significand /= 2
            binaryExponent += 1
        }

        var coefficient = QueryDecimalMagnitude(significand)
        let scale: Int64
        if binaryExponent >= 0 {
            for _ in 0..<binaryExponent { coefficient.multiply(by: 2) }
            scale = 0
        } else {
            let decimalPlaces = -binaryExponent
            for _ in 0..<decimalPlaces { coefficient.multiply(by: 5) }
            scale = Int64(decimalPlaces)
        }
        self.init(
            isNegative: negative,
            digits: coefficient.decimalDigits,
            scale: scale
        )
    }

    init(_ value: ExactDecimal) {
        self.init(
            isNegative: value.coefficient < 0,
            digits: Array(String(value.coefficient.magnitude).utf8).map {
                $0 - 48
            },
            scale: Int64(value.scale)
        )
    }

    init(_ value: Int128) {
        self.init(
            isNegative: value < 0,
            digits: Array(String(value.magnitude).utf8).map { $0 - 48 },
            scale: 0
        )
    }

    init(_ value: UInt128) {
        self.init(
            isNegative: false,
            digits: Array(String(value).utf8).map { $0 - 48 },
            scale: 0
        )
    }

    init(isNegative: Bool, digits: [UInt8], scale: Int64) {
        var digits = digits
        var scale = scale
        while digits.count > 1, digits.last == 0 {
            digits.removeLast()
            scale -= 1
        }
        self.isNegative = digits == [0] ? false : isNegative
        self.digits = digits
        self.scale = digits == [0] ? 0 : scale
    }

    func compare(to other: Self) -> Int {
        if digits == [0], other.digits == [0] { return 0 }
        if isNegative != other.isNegative { return isNegative ? -1 : 1 }

        let magnitudeComparison = compareMagnitude(to: other)
        return isNegative ? -magnitudeComparison : magnitudeComparison
    }

    private func compareMagnitude(to other: Self) -> Int {
        let leftLeadingPower = Int64(digits.count - 1) - scale
        let rightLeadingPower = Int64(other.digits.count - 1) - other.scale
        if leftLeadingPower != rightLeadingPower {
            return leftLeadingPower < rightLeadingPower ? -1 : 1
        }
        let count = max(digits.count, other.digits.count)
        for index in 0..<count {
            let left = index < digits.count ? digits[index] : 0
            let right = index < other.digits.count ? other.digits[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

private struct QueryDecimalMagnitude {
    private static let base: UInt64 = 1_000_000_000
    private var limbs: [UInt32]

    init(_ value: UInt64) {
        let lower = UInt32(value % Self.base)
        let upper = UInt32(value / Self.base)
        self.limbs = upper == 0 ? [lower] : [lower, upper]
    }

    mutating func multiply(by factor: UInt32) {
        var carry: UInt64 = 0
        for index in limbs.indices {
            let product = UInt64(limbs[index]) * UInt64(factor) + carry
            limbs[index] = UInt32(product % Self.base)
            carry = product / Self.base
        }
        if carry != 0 { limbs.append(UInt32(carry)) }
    }

    var decimalDigits: [UInt8] {
        guard let mostSignificant = limbs.last else { return [0] }
        var text = String(mostSignificant)
        if limbs.count > 1 {
            for limb in limbs.dropLast().reversed() {
                let part = String(limb)
                text += String(repeating: "0", count: 9 - part.utf8.count)
                text += part
            }
        }
        return text.utf8.map { $0 - 48 }
    }
}
