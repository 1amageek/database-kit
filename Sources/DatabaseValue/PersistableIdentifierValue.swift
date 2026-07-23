/// The canonical logical value of a persistable identifier.
///
/// A composite identifier is encoded as one nested tuple element. This keeps a
/// scalar identifier distinct from a one-component composite identifier while
/// allowing the storage key codec to emit the final key without intermediate
/// byte materialization.
public indirect enum PersistableIdentifierValue: Sendable {
    case bool(Bool)
    case int64(Int64)
    case uint64(UInt64)
    case string(String)
    case bytes(DatabaseBytes)
    case uuid(DatabaseUUID)
    case composite([PersistableIdentifierValue])

}
