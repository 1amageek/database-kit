import DatabaseTypes

/// A deterministic QueryIR structural resource-limit violation.
public enum QueryStructuralValidationError: Error, Sendable, Equatable {
    public enum Resource: String, Sendable, Equatable {
        case nestingDepth
        case retainedBytes
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
    case invalidResourceClaim(Resource)
    case invalidArrayAccessSubscriptCount(Int)
    case emptyVariadicFunctionArguments
    case invalidPatternEscape
    case unbalancedNesting
    case invalidQueryValue(QueryValueError)
    case invalidReferenceIdentifier(ReferenceIdentifierValidationError)
}

extension QueryStructuralValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .resourceLimitExceeded(let resource, let actual, let maximum):
            return "Query \(resource.rawValue) limit exceeded: \(actual) > \(maximum)"
        case .invalidResourceClaim(let resource):
            return "Query \(resource.rawValue) must use its dedicated admission operation"
        case .invalidArrayAccessSubscriptCount(let count):
            return "Array access requires one through six subscripts, received \(count)"
        case .emptyVariadicFunctionArguments:
            return "Explicit VARIADIC requires a final array argument"
        case .invalidPatternEscape:
            return "ERE pattern predicates do not accept an escape expression"
        case .unbalancedNesting:
            return "Query nesting admission is unbalanced"
        case .invalidQueryValue:
            return "Query contains an invalid query value"
        case .invalidReferenceIdentifier(let error):
            return "Query contains an invalid reference identifier: \(error)"
        }
    }
}
