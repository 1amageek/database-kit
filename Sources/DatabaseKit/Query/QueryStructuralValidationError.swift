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
    case invalidValuesRowArity(row: Int, expected: Int, actual: Int)
    case invalidCTESearchClause
    case invalidCTECycleClause
    case invalidTableFunctionSource
    case emptyDistinctOn
    case invalidSetQueryEnvelope
    case sourceAliasInTableReference
    case invalidResourceClaim(Resource)
    case invalidArrayAccessSubscriptCount(Int)
    case emptyVariadicFunctionArguments
    case invalidPatternEscape
    case emptySQLBlock
    case invalidSQLCheckpointName
    case invalidSQLControl
    case unbalancedNesting
    case invalidQueryValue(QueryValueError)
    case invalidReferenceIdentifier(ReferenceIdentifierValidationError)
}

extension QueryStructuralValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .resourceLimitExceeded(let resource, let actual, let maximum):
            return "Query \(resource.rawValue) limit exceeded: \(actual) > \(maximum)"
        case .invalidValuesRowArity(let row, let expected, let actual):
            return "VALUES row \(row) has \(actual) cells; expected \(expected)"
        case .invalidCTESearchClause:
            return "Invalid CTE SEARCH keys or generated column"
        case .invalidCTECycleClause:
            return "Invalid CTE CYCLE keys, generated columns or constants"
        case .invalidTableFunctionSource:
            return "Invalid table function name, schema or modifiers"
        case .emptyDistinctOn:
            return "DISTINCT ON requires at least one expression"
        case .invalidSetQueryEnvelope:
            return "Set operations require a query-expression envelope"
        case .sourceAliasInTableReference:
            return "A table source alias requires the source alias wrapper"
        case .invalidResourceClaim(let resource):
            return "Query \(resource.rawValue) must use its dedicated admission operation"
        case .invalidArrayAccessSubscriptCount(let count):
            return "Array access requires one through six subscripts, received \(count)"
        case .emptyVariadicFunctionArguments:
            return "Explicit VARIADIC requires a final array argument"
        case .invalidPatternEscape:
            return "ERE pattern predicates do not accept an escape expression"
        case .emptySQLBlock:
            return "An SQL block requires at least one step"
        case .invalidSQLControl:
            return "Invalid SQL semantic control payload"
        case .invalidSQLCheckpointName:
            return "An SQL checkpoint name must be nonempty and contain no NUL"
        case .unbalancedNesting:
            return "Query nesting admission is unbalanced"
        case .invalidQueryValue:
            return "Query contains an invalid query value"
        case .invalidReferenceIdentifier(let error):
            return "Query contains an invalid reference identifier: \(error)"
        }
    }
}
