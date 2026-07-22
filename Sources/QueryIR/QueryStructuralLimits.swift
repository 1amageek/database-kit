/// Resource limits applied to canonical QueryIR and text parsing.
///
/// The same limits protect SQL, SPARQL, binary QueryIR, and text input paths.
/// Syntax-specific counters supplement the global node and collection budgets.
public struct QueryStructuralLimits: Sendable, Equatable, Hashable {
    public let maximumNestingDepth: UInt64
    public let maximumInputTokens: UInt64
    public let maximumTotalNodes: UInt64
    public let maximumCollectionElements: UInt64
    public let maximumBasicGraphPatterns: UInt64
    public let maximumTriplePatterns: UInt64
    public let maximumValuesRows: UInt64
    public let maximumValuesVariables: UInt64
    public let maximumValuesCells: UInt64
    public let maximumReifiedTripleExpansions: UInt64

    public init(
        maximumNestingDepth: UInt64 = 64,
        maximumInputTokens: UInt64 = 1_000_000,
        maximumTotalNodes: UInt64 = 1_000_000,
        maximumCollectionElements: UInt64 = 1_000_000,
        maximumBasicGraphPatterns: UInt64 = 10_000,
        maximumTriplePatterns: UInt64 = 100_000,
        maximumValuesRows: UInt64 = 100_000,
        maximumValuesVariables: UInt64 = 10_000,
        maximumValuesCells: UInt64 = 100_000,
        maximumReifiedTripleExpansions: UInt64 = 100_000
    ) {
        self.maximumNestingDepth = maximumNestingDepth
        self.maximumInputTokens = maximumInputTokens
        self.maximumTotalNodes = maximumTotalNodes
        self.maximumCollectionElements = maximumCollectionElements
        self.maximumBasicGraphPatterns = maximumBasicGraphPatterns
        self.maximumTriplePatterns = maximumTriplePatterns
        self.maximumValuesRows = maximumValuesRows
        self.maximumValuesVariables = maximumValuesVariables
        self.maximumValuesCells = maximumValuesCells
        self.maximumReifiedTripleExpansions = maximumReifiedTripleExpansions
    }

    public static let `default` = QueryStructuralLimits()
}
