/// Whether NULL-bearing unique keys conflict with one another.
public enum SQLNullUniqueness: Sendable, Hashable {
    case distinct
    case notDistinct
}
