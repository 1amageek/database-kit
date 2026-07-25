import DatabaseTypes
public enum PersistableDecodingError: Error, Sendable, CustomStringConvertible {
    case missingSchema(String)
    case missingCompiledDecoder(String)
    case duplicateSchemaFieldNumber(Int)
    case duplicateSchemaFieldName(String)
    case duplicateFieldNumber(UInt32)
    case duplicateFieldName(String)
    case unknownField(number: UInt32, name: String)
    case fieldIdentityMismatch(number: UInt32, name: String)
    case invalidFieldIdentity(
        entity: String,
        number: Int,
        name: String
    )
    case unexpectedFieldOrder(
        entity: String,
        expectedNumber: UInt32,
        actualNumber: UInt32
    )
    case unconsumedField(
        entity: String,
        number: UInt32,
        name: String
    )
    case missingRequiredField(String)
    case invalidValue(field: String, expected: String)
    case invalidReference(
        field: String,
        reason: PersistableReferenceError
    )
    case invalidDate(field: String)
    case invalidNestedFieldNumber(UInt32)
    case unsupportedValue(field: String)

    public var description: String {
        switch self {
        case .missingSchema(let type):
            return "No static field schema is available for '\(type)'"
        case .missingCompiledDecoder(let type):
            return "No macro-generated persistable decoder is available for '\(type)'"
        case .duplicateSchemaFieldNumber(let number):
            return "Static persistable schema contains duplicate field number \(number)"
        case .duplicateSchemaFieldName(let name):
            return "Static persistable schema contains duplicate field name '\(name)'"
        case .duplicateFieldNumber(let number):
            return "Persisted object contains duplicate field number \(number)"
        case .duplicateFieldName(let name):
            return "Persisted object contains duplicate field name '\(name)'"
        case .unknownField(let number, let name):
            return "Persisted field #\(number) '\(name)' is not declared by the schema"
        case .fieldIdentityMismatch(let number, let name):
            return "Persisted field #\(number) and name '\(name)' resolve to different schema fields"
        case .invalidFieldIdentity(let entity, let number, let name):
            return "Compiled field #\(number) '\(name)' is invalid for '\(entity)'"
        case .unexpectedFieldOrder(
            let entity,
            let expectedNumber,
            let actualNumber
        ):
            return "Persisted fields for '\(entity)' expected field #\(expectedNumber) before field #\(actualNumber)"
        case .unconsumedField(let entity, let number, let name):
            return "Persisted field #\(number) '\(name)' was not consumed while reconstructing '\(entity)'"
        case .missingRequiredField(let field):
            return "Required persisted field '\(field)' is missing"
        case .invalidValue(let field, let expected):
            return "Persisted field '\(field)' must be encoded as \(expected)"
        case .invalidReference(let field, let reason):
            return "Persisted field '\(field)' contains an invalid reference: \(reason)"
        case .invalidDate(let field):
            return "Persisted field '\(field)' contains an invalid date"
        case .invalidNestedFieldNumber(let number):
            return "Nested persisted field number \(number) is invalid"
        case .unsupportedValue(let field):
            return "Persisted field '\(field)' uses a value that cannot be decoded by the static schema"
        }
    }
}
