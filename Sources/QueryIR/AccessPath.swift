import Foundation

/// Feature-specific access path layered on top of a logical row source.
///
/// `DataSource` stays relational/graph-oriented. Optional index- or
/// fusion-based access is represented here to preserve `QueryIR` extensibility.
public enum AccessPath: Sendable, Equatable, Hashable, Codable {
    case index(IndexScanSource)
    case fusion(FusionSource)
}

/// Type-erased description of an index-driven read.
///
/// The binder/runtime in `database-framework` is responsible for interpreting
/// `kindIdentifier` and validating `parameters`.
public struct IndexScanSource: Sendable, Equatable, Hashable, Codable {
    public let indexName: String
    public let kindIdentifier: String
    public let parameters: [String: QueryParameterValue]

    public init(
        indexName: String,
        kindIdentifier: String,
        parameters: [String: QueryParameterValue] = [:]
    ) {
        self.indexName = indexName
        self.kindIdentifier = kindIdentifier
        self.parameters = parameters
    }
}

/// Type-erased description of a fusion access path.
public struct FusionSource: Sendable, Equatable, Hashable, Codable {
    public let inputs: [IndexScanSource]
    public let strategyIdentifier: String
    public let parameters: [String: QueryParameterValue]
    public let identityField: String

    public init(
        inputs: [IndexScanSource],
        strategyIdentifier: String,
        parameters: [String: QueryParameterValue] = [:],
        identityField: String = "id"
    ) {
        self.inputs = inputs
        self.strategyIdentifier = strategyIdentifier
        self.parameters = parameters
        self.identityField = identityField
    }
}
