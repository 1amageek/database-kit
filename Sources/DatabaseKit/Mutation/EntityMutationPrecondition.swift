import DatabaseTypes

public enum EntityMutationPrecondition: Sendable, Hashable {
    case expectedVersion(identity: EntityReference, version: ByteString)
    case mustExist(EntityReference)
    case mustNotExist(EntityReference)

    public var identity: EntityReference {
        switch self {
        case .expectedVersion(let identity, _):
            return identity
        case .mustExist(let identity), .mustNotExist(let identity):
            return identity
        }
    }
}
