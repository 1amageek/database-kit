import DatabaseTypes
/// Stable scalar types supported by typed index runtimes.
public enum IndexScalarType: String, Sendable, Codable, CaseIterable {
    case int8
    case int16
    case int32
    case int64
    case uint8
    case uint16
    case uint32
    case uint64
    case float32
    case float64
    case string
    case date

    public var isNumeric: Bool {
        switch self {
        case .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64,
             .float32, .float64:
            return true
        case .string, .date:
            return false
        }
    }

    public var isFloatingPoint: Bool {
        self == .float32 || self == .float64
    }
}
