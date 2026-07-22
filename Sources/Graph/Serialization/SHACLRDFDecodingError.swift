public enum SHACLRDFDecodingError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingProperty(subject: String, predicate: String)
    case invalidIRI(String)
    case invalidLiteral(String)
    case invalidBoolean(String)
    case invalidInteger(String)
    case invalidNumber(String)
    case malformedList(String)
    case recursiveShape(String)
    case recursivePath(String)
    case invalidShapeIdentifier(String)
    case unsupportedPredicate(String)
    case unsupportedFocusNode(String)

    public var description: String {
        switch self {
        case .missingProperty(let subject, let predicate):
            return "Missing SHACL property \(predicate) on \(subject)"
        case .invalidIRI(let value):
            return "Expected an IRI, got \(value)"
        case .invalidLiteral(let value):
            return "Expected a literal, got \(value)"
        case .invalidBoolean(let value):
            return "Invalid SHACL boolean: \(value)"
        case .invalidInteger(let value):
            return "Invalid SHACL integer: \(value)"
        case .invalidNumber(let value):
            return "Invalid SHACL number: \(value)"
        case .malformedList(let value):
            return "Malformed RDF list at \(value)"
        case .recursiveShape(let value):
            return "Recursive SHACL shape is not supported: \(value)"
        case .recursivePath(let value):
            return "Recursive SHACL path is invalid: \(value)"
        case .invalidShapeIdentifier(let value):
            return "SHACL shape identifier must be an IRI or blank node: \(value)"
        case .unsupportedPredicate(let value):
            return "Unsupported SHACL predicate: \(value)"
        case .unsupportedFocusNode(let value):
            return "The SHACL value model cannot represent focus node \(value)"
        }
    }
}
