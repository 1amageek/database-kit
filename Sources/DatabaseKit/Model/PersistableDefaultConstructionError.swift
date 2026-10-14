import DatabaseTypes

/// Exact intrinsic failures while constructing an admitted static field default.
public enum PersistableDefaultConstructionError: Error, Sendable, Equatable {
    case queryValue(QueryValueError)
    case timeSpan(TimeSpanError)
}
