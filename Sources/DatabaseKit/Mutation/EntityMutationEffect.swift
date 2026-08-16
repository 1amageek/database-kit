import DatabaseTypes

public struct EntityMutationEffect: Sendable, Hashable {
    public let kind: EntityMutationKind
    public let identity: EntityReference
    public let version: ByteString?

    public init(
        kind: EntityMutationKind,
        identity: EntityReference,
        version: ByteString? = nil
    ) {
        self.kind = kind
        self.identity = identity
        self.version = version
    }
}
