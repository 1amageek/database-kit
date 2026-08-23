/// Explicit semantic grouping of Fusion inputs.
public struct FusionStage<Item: Persistable>: Sendable {
    public let source: FusionStageSource

    public init(
        @FusionInputBuilder<Item> _ content: () -> [FusionInput]
    ) {
        self.source = FusionStageSource(inputs: content())
    }
}
