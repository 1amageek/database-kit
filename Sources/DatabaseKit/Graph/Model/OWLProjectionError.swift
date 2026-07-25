import DatabaseTypes
public enum OWLProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidIndividualIRIBase(String)
    case invalidIndividualIRI(String)
    case dataPropertyRequiresLiteral
    case invalidDateTime(XSDDateTimeError)

    public var description: String {
        switch self {
        case .invalidIndividualIRIBase(let value):
            return "OWL individual IRI base must be absolute: '\(value)'"
        case .invalidIndividualIRI(let value):
            return "OWL individual IRI is invalid: '\(value)'"
        case .dataPropertyRequiresLiteral:
            return "OWL data property values must be RDF literals"
        case .invalidDateTime(let error):
            return "OWL dateTime projection failed: \(error)"
        }
    }
}
