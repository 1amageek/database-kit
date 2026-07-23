extension FieldValue {
    public var isNull: Bool {
        if case .null = self {
            return true
        }
        return false
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var int64Value: Int64? {
        switch self {
        case .int64(let value):
            return value
        case .uint64(let value) where value <= UInt64(Int64.max):
            return Int64(value)
        default:
            return nil
        }
    }

    public var uint64Value: UInt64? {
        switch self {
        case .uint64(let value):
            return value
        case .int64(let value) where value >= 0:
            return UInt64(value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int64(let value):
            return Double(value)
        case .uint64(let value):
            return Double(value)
        default:
            return nil
        }
    }

    /// Returns a numeric value represented as `Double`.
    ///
    /// Decimal conversion is intentionally explicit and may round because the
    /// destination is binary floating point. No locale or Foundation type is
    /// involved, so the result is deterministic across supported runtimes.
    public var numericDoubleValue: Double? {
        switch self {
        case .int64(let value):
            return Double(value)
        case .uint64(let value):
            return Double(value)
        case .double(let value):
            return value
        case .decimal(let coefficient, let scale):
            let magnitude = Self.powerOfTen(
                UInt32(scale >= 0 ? Int64(scale) : -Int64(scale))
            )
            return scale >= 0
                ? Double(coefficient) / magnitude
                : Double(coefficient) * magnitude
        default:
            return nil
        }
    }

    private static func powerOfTen(_ exponent: UInt32) -> Double {
        var remaining = exponent
        var factor = 10.0
        var result = 1.0
        while remaining > 0 {
            if remaining & 1 == 1 {
                result *= factor
            }
            remaining >>= 1
            if remaining > 0 {
                factor *= factor
            }
        }
        return result
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var bytesValue: DatabaseBytes? {
        guard case .bytes(let value) = self else { return nil }
        return value
    }

    public var uuidValue: DatabaseUUID? {
        guard case .uuid(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [FieldValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var objectValue: [DatabaseObjectField]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var referenceValue: PersistableIdentity? {
        guard case .reference(let value) = self else { return nil }
        return value
    }

    public var rdfTermValue: DatabaseRDFTerm? {
        guard case .rdfTerm(let value) = self else { return nil }
        return value
    }
}
