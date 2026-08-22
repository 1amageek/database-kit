
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

/// Strategy used to combine the ordered results of fusion inputs.
public enum FusionStrategy: Sendable, Equatable, Hashable {
    /// Reciprocal rank fusion with the given nonnegative rank constant.
    case reciprocalRank(rankConstant: UInt64 = 60)

    /// Sum independently normalized input scores.
    case sum

    /// Keep the maximum independently normalized input score.
    case maximum

    /// Sum independently normalized input scores after applying one weight to
    /// each input in declaration order.
    case weighted([Double])
}

/// Canonical description of a fusion access path.
public struct FusionSource: Sendable, Equatable, Hashable {
    /// Canonical annotation carrying the combined score on execution output.
    public static let scoreAnnotation = "fusion.score"

    public let inputs: [IndexScanSource]
    public let strategy: FusionStrategy
    public let identityField: String

    public init(
        inputs: [IndexScanSource],
        strategy: FusionStrategy = .reciprocalRank(),
        identityField: String = "id"
    ) {
        self.inputs = inputs
        self.strategy = strategy
        self.identityField = identityField
    }
}
