/// A cross-entity property-graph traversal in a Fusion plan.
public struct FusionConnectedSource: Sendable, Equatable, Hashable {
    public let edgeEntity: String
    public let edgePartitions: FieldObject
    public let selection: FusionIndexSelection
    public let resultField: FieldIdentity
    public let origin: String
    public let edgeLabel: String?
    public let direction: FusionConnectedDirection
    public let maximumHops: UInt64

    public init(
        edgeEntity: String,
        edgePartitions: FieldObject = FieldObject(),
        selection: FusionIndexSelection,
        resultField: FieldIdentity,
        origin: String,
        edgeLabel: String? = nil,
        direction: FusionConnectedDirection = .outgoing,
        maximumHops: UInt64 = 1
    ) {
        self.edgeEntity = edgeEntity
        self.edgePartitions = edgePartitions
        self.selection = selection
        self.resultField = resultField
        self.origin = origin
        self.edgeLabel = edgeLabel
        self.direction = direction
        self.maximumHops = maximumHops
    }
}
