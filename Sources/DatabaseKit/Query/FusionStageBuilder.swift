/// Builds ordered Fusion stages without exposing an execution schedule.
@resultBuilder
public enum FusionStageBuilder<Item: Persistable> {
    public static func buildExpression<Input: FusionQueryInput>(
        _ input: Input
    ) -> [FusionStageSource] where Input.Item == Item {
        [FusionStageSource(inputs: [input.fusionInput])]
    }

    public static func buildExpression(
        _ stage: FusionStage<Item>
    ) -> [FusionStageSource] {
        [stage.source]
    }

    public static func buildBlock(
        _ components: [FusionStageSource]...
    ) -> [FusionStageSource] {
        components.flatMap { $0 }
    }

    public static func buildOptional(
        _ component: [FusionStageSource]?
    ) -> [FusionStageSource] {
        component ?? []
    }

    public static func buildEither(
        first component: [FusionStageSource]
    ) -> [FusionStageSource] {
        component
    }

    public static func buildEither(
        second component: [FusionStageSource]
    ) -> [FusionStageSource] {
        component
    }

    public static func buildArray(
        _ components: [[FusionStageSource]]
    ) -> [FusionStageSource] {
        components.flatMap { $0 }
    }
}
