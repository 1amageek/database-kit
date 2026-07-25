import DatabaseTypes
public enum PersistableEncodingError: Error, Sendable, Equatable {
    case missingCompiledEncoder(String)
    case invalidSchema(entity: String, reason: String)
    case fieldNotRepresentable(entity: String, field: String)
    case invalidScalar(type: String, reason: String)
}
