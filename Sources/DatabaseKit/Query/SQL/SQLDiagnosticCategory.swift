/// Semantic failure classes shared by SQL adapters.
public enum SQLDiagnosticCategory: String, Sendable, Hashable {
    case syntax, name, type, cardinality, constraint, numeric, data
    case serialization, transaction, cancellation, unsupported, resource
    case authorization, internalError
}
