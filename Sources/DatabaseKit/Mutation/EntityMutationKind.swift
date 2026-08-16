public enum EntityMutationKind: UInt8, Sendable, Hashable {
    case insert = 1
    case update = 2
    case upsert = 3
    case delete = 4
}
