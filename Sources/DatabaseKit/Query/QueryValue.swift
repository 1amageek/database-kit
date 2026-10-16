import DatabaseTypes

public enum QueryValue: Sendable, Hashable {
    case primitive(FieldValue)
    case numeric(QueryNumericValue)
    case json(QueryJSONValue)
    case jsonb(QueryJSONBValue)
    case array(QueryArrayValue)
    case interval(QueryIntervalValue)
    case time(QueryTimeValue)
    case timeWithTimeZone(QueryTimeWithTimeZoneValue)
    case dateInfinity(QueryTemporalInfinity)
    case timestampInfinity(QueryTemporalInfinity, withTimeZone: Bool)
    case intervalInfinity(QueryTemporalInfinity)

    public var isNull: Bool {
        if case .primitive(.null) = self { return true }
        return false
    }
}
