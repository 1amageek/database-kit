/// The canonical logical shape of a persistable identifier.
///
/// Identifier types are intentionally narrower than `FieldValue`. Values
/// with ambiguous equality or ordering semantics, such as floating-point
/// numbers, are not valid identifiers.
public indirect enum PersistableIdentifierType: Sendable, Hashable {
    case bool
    case int64
    case uint64
    case string
    case bytes
    case uuid
    case composite([PersistableIdentifierType])
}
