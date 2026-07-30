import DatabaseTypes
/// Errors produced while decoding canonical index metadata.
public enum IndexKindMetadataError: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownIdentifier(String)
    case kindMismatch(expected: String, actual: String)
    case subspaceStructureMismatch(
        identifier: String,
        expected: SubspaceStructure,
        actual: SubspaceStructure
    )
    case missingMetadata(identifier: String, key: String)
    case invalidMetadata(identifier: String, key: String)
    case unexpectedMetadata(identifier: String, key: String)
    case invalidFieldCount(identifier: String, expected: String, actual: Int)
    case invalidFieldName(identifier: String, fieldName: String)

    public var description: String {
        switch self {
        case .unknownIdentifier(let identifier):
            return "Unknown index kind identifier '\(identifier)'"
        case .kindMismatch(let expected, let actual):
            return "Expected index kind '\(expected)', got '\(actual)'"
        case .subspaceStructureMismatch(let identifier, let expected, let actual):
            return "Index kind '\(identifier)' expected subspace '\(expected)', got '\(actual)'"
        case .missingMetadata(let identifier, let key):
            return "Index kind '\(identifier)' is missing metadata '\(key)'"
        case .invalidMetadata(let identifier, let key):
            return "Index kind '\(identifier)' has invalid metadata '\(key)'"
        case .unexpectedMetadata(let identifier, let key):
            return "Index kind '\(identifier)' has unexpected metadata '\(key)'"
        case .invalidFieldCount(let identifier, let expected, let actual):
            return "Index kind '\(identifier)' expected \(expected) fields, got \(actual)"
        case .invalidFieldName(let identifier, let fieldName):
            return "Index kind '\(identifier)' has invalid field name '\(fieldName)'"
        }
    }
}

extension IndexKindMetadata {
    public func validateIdentity(
        identifier expectedIdentifier: String,
        subspaceStructure expectedSubspaceStructure: SubspaceStructure
    ) throws(IndexKindMetadataError) {
        guard identifier == expectedIdentifier else {
            throw .kindMismatch(expected: expectedIdentifier, actual: identifier)
        }
        guard subspaceStructure == expectedSubspaceStructure else {
            throw .subspaceStructureMismatch(
                identifier: identifier,
                expected: expectedSubspaceStructure,
                actual: subspaceStructure
            )
        }
    }

    public func validateMetadataKeys(
        required: Set<String> = [],
        optional: Set<String> = []
    ) throws(IndexKindMetadataError) {
        for key in required where metadata[key] == nil {
            throw .missingMetadata(identifier: identifier, key: key)
        }
        let allowed = required.union(optional)
        for key in metadata.keys where !allowed.contains(key) {
            throw .unexpectedMetadata(identifier: identifier, key: key)
        }
    }

    public func validateFieldCount(
        _ expected: Int
    ) throws(IndexKindMetadataError) {
        guard fieldNames.count == expected else {
            throw .invalidFieldCount(
                identifier: identifier,
                expected: String(expected),
                actual: fieldNames.count
            )
        }
        try validateFieldNames()
    }

    public func validateFieldCount(
        minimum: Int,
        maximum: Int? = nil
    ) throws(IndexKindMetadataError) {
        let upperBound = maximum ?? Int.max
        guard fieldNames.count >= minimum, fieldNames.count <= upperBound else {
            let expected = maximum.map { "\(minimum)...\($0)" } ?? "at least \(minimum)"
            throw .invalidFieldCount(
                identifier: identifier,
                expected: expected,
                actual: fieldNames.count
            )
        }
        try validateFieldNames()
    }

    public func validateFieldNames() throws(IndexKindMetadataError) {
        for fieldName in fieldNames where fieldName.isEmpty {
            throw .invalidFieldName(identifier: identifier, fieldName: fieldName)
        }
    }

    public func requireString(
        _ key: String
    ) throws(IndexKindMetadataError) -> String {
        guard let value = metadata[key]?.stringValue, !value.isEmpty else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return value
    }

    public func requireInt(
        _ key: String
    ) throws(IndexKindMetadataError) -> Int {
        guard let fieldValue = metadata[key],
              let value = Self.int(exactly: fieldValue) else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return value
    }

    public func requireDouble(
        _ key: String
    ) throws(IndexKindMetadataError) -> Double {
        guard let fieldValue = metadata[key] else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        switch fieldValue {
        case .float32(let value):
            return Double(value)
        case .float64(let value):
            return value
        default:
            throw .invalidMetadata(identifier: identifier, key: key)
        }
    }

    public func requireTimeSpan(
        _ key: String
    ) throws(IndexKindMetadataError) -> TimeSpan {
        guard let fieldValue = metadata[key],
              case .timeSpan(let value) = fieldValue else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return value
    }

    public func requireBool(
        _ key: String
    ) throws(IndexKindMetadataError) -> Bool {
        guard let value = metadata[key]?.boolValue else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return value
    }

    public func requireStringArray(
        _ key: String
    ) throws(IndexKindMetadataError) -> [String] {
        guard case .array(let values) = metadata[key] else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        var strings: [String] = []
        strings.reserveCapacity(values.count)
        for value in values {
            guard case .string(let string) = value else {
                throw .invalidMetadata(identifier: identifier, key: key)
            }
            strings.append(string)
        }
        return strings
    }

    public func requireIntArray(
        _ key: String
    ) throws(IndexKindMetadataError) -> [Int] {
        guard case .array(let values) = metadata[key] else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        var integers: [Int] = []
        integers.reserveCapacity(values.count)
        for value in values {
            guard let integer = Self.int(exactly: value) else {
                throw .invalidMetadata(identifier: identifier, key: key)
            }
            integers.append(integer)
        }
        return integers
    }

    public func requireRDFTerm(
        _ key: String
    ) throws(IndexKindMetadataError) -> RDFTerm {
        guard let value = metadata[key]?.rdfTermValue else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return value
    }

    public func requireScalarType(
        _ key: String
    ) throws(IndexKindMetadataError) -> IndexScalarType {
        let rawValue = try requireString(key)
        guard let scalarType = IndexScalarType(rawValue: rawValue) else {
            throw .invalidMetadata(identifier: identifier, key: key)
        }
        return scalarType
    }

    private static func int(exactly value: FieldValue) -> Int? {
        switch value {
        case .int8(let value):
            return Int(value)
        case .int16(let value):
            return Int(value)
        case .int32(let value):
            return Int(value)
        case .int64(let value):
            return Int(exactly: value)
        case .uint8(let value):
            return Int(value)
        case .uint16(let value):
            return Int(value)
        case .uint32(let value):
            return Int(exactly: value)
        case .uint64(let value):
            return Int(exactly: value)
        default:
            return nil
        }
    }
}
