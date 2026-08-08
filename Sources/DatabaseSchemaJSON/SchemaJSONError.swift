public enum SchemaJSONError: Error, Sendable, Equatable {
    case inputTooLarge(actual: Int, maximum: Int)
    case nestingTooDeep(maximum: Int)
    case collectionTooLarge(path: String, actual: Int, maximum: Int)
    case invalidSyntax(message: String, byteOffset: Int)
    case duplicateKey(key: String, byteOffset: Int)
    case missingField(path: String)
    case unknownField(path: String)
    case typeMismatch(path: String, expected: String)
    case invalidValue(path: String, reason: String)
    case invalidSchema(reason: String)
    case outputTooLarge(actual: Int, maximum: Int)
}

extension SchemaJSONError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .inputTooLarge(let actual, let maximum):
            "Schema JSON input is \(actual) bytes; maximum is \(maximum)"
        case .nestingTooDeep(let maximum):
            "Schema JSON nesting exceeds \(maximum)"
        case .collectionTooLarge(let path, let actual, let maximum):
            "Schema JSON collection '\(path)' has \(actual) elements; maximum is \(maximum)"
        case .invalidSyntax(let message, let byteOffset):
            "\(message) at byte \(byteOffset)"
        case .duplicateKey(let key, let byteOffset):
            "Duplicate Schema JSON key '\(key)' at byte \(byteOffset)"
        case .missingField(let path):
            "Missing Schema JSON field '\(path)'"
        case .unknownField(let path):
            "Unknown Schema JSON field '\(path)'"
        case .typeMismatch(let path, let expected):
            "Schema JSON field '\(path)' must be \(expected)"
        case .invalidValue(let path, let reason):
            "Invalid Schema JSON value at '\(path)': \(reason)"
        case .invalidSchema(let reason):
            "Invalid schema: \(reason)"
        case .outputTooLarge(let actual, let maximum):
            "Schema JSON output is \(actual) bytes; maximum is \(maximum)"
        }
    }
}
