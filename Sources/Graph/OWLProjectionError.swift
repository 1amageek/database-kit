public enum OWLProjectionError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidIndividualIRIBase(String)
    case dataPropertyRequiresLiteral

    public var description: String {
        switch self {
        case .invalidIndividualIRIBase(let value):
            return "OWL individual IRI base must be absolute: '\(value)'"
        case .dataPropertyRequiresLiteral:
            return "OWL data property values must be RDF literals"
        }
    }
}
