/// SQL data types for CAST
public indirect enum DataType: Sendable, Equatable, Hashable {
    case boolean
    case smallint
    case integer
    case bigint
    case real
    case doublePrecision
    case decimal(precision: Int?, scale: Int?)
    case char(length: Int?)
    case varchar(length: Int?)
    case text
    case date
    case time(withTimeZone: Bool, precision: Int? = nil)
    case timestamp(withTimeZone: Bool, precision: Int? = nil)
    case interval(fields: SQLIntervalFields? = nil, precision: Int? = nil)
    case binary(length: Int?)
    case varbinary(length: Int?)
    case blob
    case json
    case jsonb
    case uuid
    case array(DataType)
    case custom(String, schema: String? = nil)  // For database-specific types
    case composite(QueryCompositeType)
}
