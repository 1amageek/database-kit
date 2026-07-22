/// A request-local admission ledger shared by text parsers and QueryIR walkers.
///
/// Every claim is checked before the caller retains the corresponding AST node
/// or collection element. The ledger is a value type and must not be shared
/// across concurrent requests.
public struct QueryStructuralResourceLedger: Sendable {
    public let limits: QueryStructuralLimits

    private var nestingDepth: UInt64 = 0
    private var inputTokens: UInt64 = 0
    private var totalNodes: UInt64 = 0
    private var collectionElements: UInt64 = 0
    private var basicGraphPatterns: UInt64 = 0
    private var triplePatterns: UInt64 = 0
    private var valuesRows: UInt64 = 0
    private var valuesVariables: UInt64 = 0
    private var valuesCells: UInt64 = 0
    private var reifiedTripleExpansions: UInt64 = 0

    public init(limits: QueryStructuralLimits = .default) {
        self.limits = limits
    }

    public mutating func enterNesting(
    ) throws(QueryStructuralValidationError) {
        let next = try checkedTotal(
            current: nestingDepth,
            amount: 1,
            resource: .nestingDepth,
            maximum: limits.maximumNestingDepth
        )
        nestingDepth = next
    }

    public mutating func leaveNesting() {
        precondition(nestingDepth > 0)
        nestingDepth -= 1
    }

    public func validateNestingDepth(
        _ depth: UInt64
    ) throws(QueryStructuralValidationError) {
        guard depth <= limits.maximumNestingDepth else {
            throw .resourceLimitExceeded(
                resource: .nestingDepth,
                actual: depth,
                maximum: limits.maximumNestingDepth
            )
        }
    }

    public mutating func consume(
        _ resource: QueryStructuralValidationError.Resource,
        amount: UInt64 = 1
    ) throws(QueryStructuralValidationError) {
        switch resource {
        case .nestingDepth:
            preconditionFailure("Nesting depth must use enterNesting or validateNestingDepth")
        case .inputTokens:
            inputTokens = try checkedTotal(
                current: inputTokens,
                amount: amount,
                resource: resource,
                maximum: limits.maximumInputTokens
            )
        case .totalNodes:
            totalNodes = try checkedTotal(
                current: totalNodes,
                amount: amount,
                resource: resource,
                maximum: limits.maximumTotalNodes
            )
        case .collectionElements:
            collectionElements = try checkedTotal(
                current: collectionElements,
                amount: amount,
                resource: resource,
                maximum: limits.maximumCollectionElements
            )
        case .basicGraphPatterns:
            basicGraphPatterns = try checkedTotal(
                current: basicGraphPatterns,
                amount: amount,
                resource: resource,
                maximum: limits.maximumBasicGraphPatterns
            )
        case .triplePatterns:
            triplePatterns = try checkedTotal(
                current: triplePatterns,
                amount: amount,
                resource: resource,
                maximum: limits.maximumTriplePatterns
            )
        case .valuesRows:
            valuesRows = try checkedTotal(
                current: valuesRows,
                amount: amount,
                resource: resource,
                maximum: limits.maximumValuesRows
            )
        case .valuesVariables:
            valuesVariables = try checkedTotal(
                current: valuesVariables,
                amount: amount,
                resource: resource,
                maximum: limits.maximumValuesVariables
            )
        case .valuesCells:
            valuesCells = try checkedTotal(
                current: valuesCells,
                amount: amount,
                resource: resource,
                maximum: limits.maximumValuesCells
            )
        case .reifiedTripleExpansions:
            reifiedTripleExpansions = try checkedTotal(
                current: reifiedTripleExpansions,
                amount: amount,
                resource: resource,
                maximum: limits.maximumReifiedTripleExpansions
            )
        }
    }

    private func checkedTotal(
        current: UInt64,
        amount: UInt64,
        resource: QueryStructuralValidationError.Resource,
        maximum: UInt64
    ) throws(QueryStructuralValidationError) -> UInt64 {
        let (actual, overflow) = current.addingReportingOverflow(amount)
        guard !overflow, actual <= maximum else {
            throw .resourceLimitExceeded(
                resource: resource,
                actual: overflow ? UInt64.max : actual,
                maximum: maximum
            )
        }
        return actual
    }
}
