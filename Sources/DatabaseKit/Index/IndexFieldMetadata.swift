/// The type-erased identity and ordering of a field selected by an index.
public struct IndexFieldMetadata: Sendable, Hashable {
    public let identity: FieldIdentity
    public let order: IndexFieldOrder

    public init(
        identity: FieldIdentity,
        order: IndexFieldOrder = .ascending
    ) {
        self.identity = identity
        self.order = order
    }

    public var name: String {
        identity.name
    }

    public var number: Int {
        identity.number
    }
}
