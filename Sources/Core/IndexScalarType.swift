/// Stable scalar types supported by typed index runtimes.
public enum IndexScalarType: String, Sendable, Codable, CaseIterable {
    case int
    case int8
    case int16
    case int32
    case int64
    case uint
    case uint8
    case uint16
    case uint32
    case uint64
    case float
    case double
    case string
    case date

    public var isNumeric: Bool {
        switch self {
        case .int, .int8, .int16, .int32, .int64,
             .uint, .uint8, .uint16, .uint32, .uint64,
             .float, .double:
            return true
        case .string, .date:
            return false
        }
    }

    public var isFloatingPoint: Bool {
        self == .float || self == .double
    }
}
