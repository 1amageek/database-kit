public enum PersistableEncodingError: Error, Sendable, Equatable {
    case invalidSchema(entity: String, reason: String)
    case fieldNotRepresentable(entity: String, field: String)
}
