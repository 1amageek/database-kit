/// The canonical logical shape of a persistable identifier.
///
/// Identifier types are intentionally narrower than `FieldValue`. Values
/// with ambiguous equality or ordering semantics, such as floating-point
/// numbers, are not valid identifiers.
public indirect enum PersistableIdentifierType: Sendable, Hashable {
    case bool
    case int8
    case int16
    case int32
    case int64
    case uint8
    case uint16
    case uint32
    case uint64
    case string
    case bytes
    case uuid
    case composite([PersistableIdentifierType])
}
