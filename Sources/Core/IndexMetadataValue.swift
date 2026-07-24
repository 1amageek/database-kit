import DatabaseTypes
/// IndexMetadataValue - Sendable, Hashable, and Codable metadata value
///
/// Supports common types that can appear in IndexKind Codable representations.
/// Used for both IndexKind-specific metadata (e.g., dimensions, metric)
/// and CommonIndexOptions (e.g., unique, sparse, storedFieldNames).

public enum IndexMetadataValue: Sendable, Hashable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case intArray([Int])
    case rdfTerm(RDFTerm)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    private enum ValueType: String, Codable {
        case string, int, double, bool, stringArray, intArray, rdfTerm
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case .int:
            let value = try container.decode(Int.self, forKey: .value)
            self = .int(value)
        case .double:
            let value = try container.decode(Double.self, forKey: .value)
            self = .double(value)
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        case .stringArray:
            let value = try container.decode([String].self, forKey: .value)
            self = .stringArray(value)
        case .intArray:
            let value = try container.decode([Int].self, forKey: .value)
            self = .intArray(value)
        case .rdfTerm:
            let value = try container.decode(RDFTerm.self, forKey: .value)
            self = .rdfTerm(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .stringArray(let value):
            try container.encode(ValueType.stringArray, forKey: .type)
            try container.encode(value, forKey: .value)
        case .intArray(let value):
            try container.encode(ValueType.intArray, forKey: .type)
            try container.encode(value, forKey: .value)
        case .rdfTerm(let value):
            try container.encode(ValueType.rdfTerm, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    // MARK: - Value Accessors

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }

    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    public var stringArrayValue: [String]? {
        if case .stringArray(let v) = self { return v }
        return nil
    }

    public var intArrayValue: [Int]? {
        if case .intArray(let v) = self { return v }
        return nil
    }

    public var rdfTermValue: RDFTerm? {
        if case .rdfTerm(let value) = self { return value }
        return nil
    }
}
import DatabaseValue
import DatabaseValueCodable
