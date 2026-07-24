/// Canonical database field value shared by schemas, queries, wire frames, and runtimes.
///
/// The enum preserves the declared storage type. Query-language numeric coercion
/// belongs to the query evaluator and must not change value identity or hashing.
public indirect enum FieldValue: Sendable {
    case null
    case bool(Bool)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case float32(Float)
    case float64(Double)
    case decimal(coefficient: Int64, scale: Int32)
    case string(String)
    case bytes(DatabaseBytes)
    case date(DatabaseDate)
    case timestamp(DatabaseTimestamp)
    case uuid(DatabaseUUID)
    case array([FieldValue])
    case object([DatabaseObjectField])
    case reference(PersistableIdentity)
    case rdfTerm(DatabaseRDFTerm)
}
