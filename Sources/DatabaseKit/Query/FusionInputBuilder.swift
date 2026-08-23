/// Builds the inputs of one explicitly grouped Fusion stage.
@resultBuilder
public enum FusionInputBuilder<Item: Persistable> {
    public static func buildExpression<Input: FusionQueryInput>(
        _ input: Input
    ) -> [FusionInput] where Input.Item == Item {
        [input.fusionInput]
    }

    public static func buildBlock(_ components: [FusionInput]...) -> [FusionInput] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [FusionInput]?) -> [FusionInput] {
        component ?? []
    }

    public static func buildEither(first component: [FusionInput]) -> [FusionInput] {
        component
    }

    public static func buildEither(second component: [FusionInput]) -> [FusionInput] {
        component
    }

    public static func buildArray(_ components: [[FusionInput]]) -> [FusionInput] {
        components.flatMap { $0 }
    }
}
