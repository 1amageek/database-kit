/// The read points that fixed the result of one database operation.
public enum DatabaseReadConsistency: Sendable, Hashable {
    case transactional(DomainReadPoint)
    case federated([DomainReadPoint])
}
