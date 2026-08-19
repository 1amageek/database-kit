
import DatabaseTypes

/// Feature-specific access path layered on top of a logical row source.
///
/// `DataSource` stays relational/graph-oriented. Optional index- or
/// fusion-based access is represented here to preserve `QueryIR` extensibility.
public enum AccessPath: Sendable, Equatable, Hashable {
    case index(IndexScanSource)
    case fusion(FusionSource)
}

/// Description of an index-driven read.
public struct IndexScanSource: Sendable, Equatable, Hashable {
    public let indexName: String
    public let indexType: IndexType
    public let parameters: [String: FieldValue]

    public init(
        indexName: String,
        indexType: IndexType,
        parameters: [String: FieldValue] = [:]
    ) {
        self.indexName = indexName
        self.indexType = indexType
        self.parameters = parameters
    }
}

/// Type-erased description of a fusion access path.
public struct FusionSource: Sendable, Equatable, Hashable {
    public let inputs: [IndexScanSource]
    public let strategyIdentifier: String
    public let parameters: [String: FieldValue]
    public let identityField: String

    public init(
        inputs: [IndexScanSource],
        strategyIdentifier: String,
        parameters: [String: FieldValue] = [:],
        identityField: String = "id"
    ) {
        self.inputs = inputs
        self.strategyIdentifier = strategyIdentifier
        self.parameters = parameters
        self.identityField = identityField
    }
}
