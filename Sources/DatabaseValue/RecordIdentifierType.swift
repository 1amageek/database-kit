/// The canonical logical shape of a persisted record identifier.
///
/// Identifier types are intentionally narrower than `DatabaseValue`. Values
/// with ambiguous equality or ordering semantics, such as floating-point
/// numbers, are not valid identifiers.
public indirect enum RecordIdentifierType: Sendable, Hashable {
    case bool
    case int64
    case uint64
    case string
    case bytes
    case uuid
    case composite([RecordIdentifierType])
}
