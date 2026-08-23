/// An ordered group of Fusion inputs sharing one incoming candidate set.
public struct FusionStageSource: Sendable, Equatable, Hashable {
    public let inputs: [FusionInput]

    public init(inputs: [FusionInput]) {
        self.inputs = inputs
    }
}
