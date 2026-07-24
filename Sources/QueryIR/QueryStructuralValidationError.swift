import DatabaseTypes

/// A deterministic QueryIR structural resource-limit violation.
public enum QueryStructuralValidationError: Error, Sendable, Equatable {
    public enum Resource: String, Sendable, Equatable {
        case nestingDepth
        case inputTokens
        case totalNodes
        case collectionElements
        case basicGraphPatterns
        case triplePatterns
        case valuesRows
        case valuesVariables
        case valuesCells
        case reifiedTripleExpansions
    }

    case resourceLimitExceeded(
        resource: Resource,
        actual: UInt64,
        maximum: UInt64
    )
    case invalidReferenceIdentifier(ReferenceIdentifierValidationError)
}

extension QueryStructuralValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .resourceLimitExceeded(let resource, let actual, let maximum):
            return "Query \(resource.rawValue) limit exceeded: \(actual) > \(maximum)"
        case .invalidReferenceIdentifier(let error):
            return "Query contains an invalid reference identifier: \(error)"
        }
    }
}
