public enum DatabaseRecordDecodingError: Error, Sendable, CustomStringConvertible {
    case missingSchema(String)
    case missingCompiledDecoder(String)
    case duplicateSchemaFieldNumber(Int)
    case duplicateSchemaFieldName(String)
    case duplicateFieldNumber(UInt32)
    case duplicateFieldName(String)
    case unknownField(number: UInt32, name: String)
    case fieldIdentityMismatch(number: UInt32, name: String)
    case missingRequiredField(String)
    case invalidValue(field: String, expected: String)
    case invalidDate(field: String)
    case invalidNestedFieldNumber(UInt32)
    case unsupportedValue(field: String)

    public var description: String {
        switch self {
        case .missingSchema(let type):
            return "No static field schema is available for '\(type)'"
        case .missingCompiledDecoder(let type):
            return "No macro-generated record decoder is available for '\(type)'"
        case .duplicateSchemaFieldNumber(let number):
            return "Static record schema contains duplicate field number \(number)"
        case .duplicateSchemaFieldName(let name):
            return "Static record schema contains duplicate field name '\(name)'"
        case .duplicateFieldNumber(let number):
            return "Record contains duplicate field number \(number)"
        case .duplicateFieldName(let name):
            return "Record contains duplicate field name '\(name)'"
        case .unknownField(let number, let name):
            return "Record field #\(number) '\(name)' is not declared by the schema"
        case .fieldIdentityMismatch(let number, let name):
            return "Record field #\(number) and name '\(name)' resolve to different schema fields"
        case .missingRequiredField(let field):
            return "Required record field '\(field)' is missing"
        case .invalidValue(let field, let expected):
            return "Record field '\(field)' must be encoded as \(expected)"
        case .invalidDate(let field):
            return "Record field '\(field)' contains an invalid date"
        case .invalidNestedFieldNumber(let number):
            return "Nested record field number \(number) is invalid"
        case .unsupportedValue(let field):
            return "Record field '\(field)' uses a value that cannot be decoded by the static schema"
        }
    }
}
