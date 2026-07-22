public indirect enum DatabaseValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int64(Int64)
    case uint64(UInt64)
    case double(Double)
    case decimal(coefficient: Int64, scale: Int32)
    case string(String)
    case bytes(DatabaseBytes)
    case date(DatabaseDate)
    case timestamp(DatabaseTimestamp)
    case uuid(DatabaseUUID)
    case array([DatabaseValue])
    case object([DatabaseObjectField])
    case reference(RecordIdentity)
    case rdfTerm(DatabaseRDFTerm)
}
