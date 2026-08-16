import DatabaseTypes

public struct EntityMutationChange: Sendable, Hashable {
    public let kind: EntityMutationKind
    public let identity: EntityReference
    public let fields: FieldObject

    public init(
        kind: EntityMutationKind,
        identity: EntityReference,
        fields: FieldObject = FieldObject()
    ) {
        self.kind = kind
        self.identity = identity
        self.fields = fields
    }
}
