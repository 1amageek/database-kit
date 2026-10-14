import DatabaseTypes

public enum QueryValue: Sendable, Hashable {
    case primitive(FieldValue)
    case numeric(QueryNumericValue)
    case json(QueryJSONValue)
    case jsonb(QueryJSONBValue)
    case array(QueryArrayValue)
    case interval(QueryIntervalValue)

    public var isNull: Bool {
        if case .primitive(.null) = self { return true }
        return false
    }
}
