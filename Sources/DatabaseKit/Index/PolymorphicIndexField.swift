/// A protocol-level field selection resolved against every concrete member.
public struct PolymorphicIndexField: Sendable, Hashable {
    public let name: String
    public let order: IndexFieldOrder

    public init(
        name: String,
        order: IndexFieldOrder = .ascending
    ) {
        self.name = name
        self.order = order
    }
}
