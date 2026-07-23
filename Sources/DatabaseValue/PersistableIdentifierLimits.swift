/// Resource limits shared by every persistable-identifier boundary.
public struct PersistableIdentifierLimits: Sendable, Hashable {
    public let maximumCompositeDepth: Int
    public let maximumComponentCount: Int

    public init(
        maximumCompositeDepth: Int,
        maximumComponentCount: Int
    ) {
        precondition(maximumCompositeDepth >= 0)
        precondition(maximumComponentCount > 0)
        self.maximumCompositeDepth = maximumCompositeDepth
        self.maximumComponentCount = maximumComponentCount
    }

    public static let `default` = PersistableIdentifierLimits(
        maximumCompositeDepth: 16,
        maximumComponentCount: 128
    )
}
