import DatabaseTypes
public enum OWLProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidIndividualIRIBase(String)
    case invalidIndividualIRI(String)
    case invalidClassIRI(String, RDFIRIError)
    case invalidPropertyIRI(String, RDFIRIError)
    case invalidVocabularyIRI(String, RDFIRIError)
    case dataPropertyRequiresLiteral
    case invalidDateTime(XSDDateTimeFormatError)

    public var description: String {
        switch self {
        case .invalidIndividualIRIBase(let value):
            return "OWL individual IRI base must be absolute: '\(value)'"
        case .invalidIndividualIRI(let value):
            return "OWL individual IRI is invalid: '\(value)'"
        case .invalidClassIRI(let value, let error):
            return "OWL class IRI '\(value)' is invalid: \(error)"
        case .invalidPropertyIRI(let value, let error):
            return "OWL property IRI '\(value)' is invalid: \(error)"
        case .invalidVocabularyIRI(let value, let error):
            return "OWL vocabulary IRI '\(value)' is invalid: \(error)"
        case .dataPropertyRequiresLiteral:
            return "OWL data property values must be RDF literals"
        case .invalidDateTime(let error):
            return "OWL dateTime projection failed: \(error)"
        }
    }
}
