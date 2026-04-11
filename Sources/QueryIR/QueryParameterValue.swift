import Foundation

/// Structured query-time parameter value for type-erased access paths.
///
/// This is intentionally separate from `Literal` and `IndexMetadataValue`:
/// - `Literal` models query expressions.
/// - `IndexMetadataValue` models schema metadata.
/// - `QueryParameterValue` models runtime parameters sent to the read binder.
public indirect enum QueryParameterValue: Sendable, Equatable, Hashable, Codable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case binary(Data)
    case array([QueryParameterValue])
    case object([String: QueryParameterValue])

    public init?(_ value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let value as Bool:
            self = .bool(value)
        case let value as Int:
            self = .int(Int64(value))
        case let value as Int8:
            self = .int(Int64(value))
        case let value as Int16:
            self = .int(Int64(value))
        case let value as Int32:
            self = .int(Int64(value))
        case let value as Int64:
            self = .int(value)
        case let value as UInt:
            self = .int(Int64(value))
        case let value as UInt8:
            self = .int(Int64(value))
        case let value as UInt16:
            self = .int(Int64(value))
        case let value as UInt32:
            self = .int(Int64(value))
        case let value as UInt64:
            self = .int(Int64(bitPattern: value))
        case let value as Float:
            self = .double(Double(value))
        case let value as Double:
            self = .double(value)
        case let value as String:
            self = .string(value)
        case let value as Data:
            self = .binary(value)
        case let value as [QueryParameterValue]:
            self = .array(value)
        case let value as [Bool]:
            self = .array(value.map(Self.bool))
        case let value as [Int]:
            self = .array(value.map { .int(Int64($0)) })
        case let value as [Int64]:
            self = .array(value.map(Self.int))
        case let value as [Float]:
            self = .array(value.map { .double(Double($0)) })
        case let value as [Double]:
            self = .array(value.map(Self.double))
        case let value as [String]:
            self = .array(value.map(Self.string))
        case let value as [String: QueryParameterValue]:
            self = .object(value)
        case let value as [Any]:
            let converted = value.compactMap(QueryParameterValue.init)
            guard converted.count == value.count else { return nil }
            self = .array(converted)
        case let value as [String: Any]:
            let converted = value.compactMapValues(QueryParameterValue.init)
            guard converted.count == value.count else { return nil }
            self = .object(converted)
        case nil as Any?:
            self = .null
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var int64Value: Int64? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var dataValue: Data? {
        guard case .binary(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [QueryParameterValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var objectValue: [String: QueryParameterValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
