/// A typed, context-free Fusion query.
public struct FusionQuery<Item: Persistable>: Sendable {
    public let source: FusionSource
    public let resultLimit: UInt64?

    public init(
        @FusionStageBuilder<Item> _ content: () -> [FusionStageSource]
    ) {
        self.source = FusionSource(stages: content())
        self.resultLimit = nil
    }

    private init(source: FusionSource, resultLimit: UInt64?) {
        self.source = source
        self.resultLimit = resultLimit
    }

    public func strategy(_ strategy: FusionStrategy) -> Self {
        Self(
            source: FusionSource(
                stages: source.stages,
                strategy: strategy
            ),
            resultLimit: resultLimit
        )
    }

    public func limit(_ count: UInt64) -> Self {
        Self(source: source, resultLimit: count)
    }

    public var selectQuery: SelectQuery {
        SelectQuery(
            projection: .all,
            source: .table(TableRef(table: Item.persistableType)),
            accessPath: .fusion(source),
            limit: resultLimit
        )
    }
}
