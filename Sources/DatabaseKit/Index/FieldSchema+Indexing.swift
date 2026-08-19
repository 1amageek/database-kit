extension FieldSchema {
    /// Whether each value represented by the field has a canonical ordering.
    ///
    /// For an array field, `type` describes the element type. Cardinality is
    /// intentionally not considered here so a single-field scalar index can
    /// index each array element independently.
    package var valuesHaveCanonicalOrdering: Bool {
        switch type {
        case .bool,
             .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .decimal,
             .string, .bytes,
             .date, .time, .dateTime, .timestamp,
             .timeSpan, .calendarPeriod,
             .uuid, .rdfTerm, .reference, .enum:
            return true
        case .geographicPoint, .geographicPosition, .vector, .object, .nested:
            return false
        }
    }

    /// Whether the field has a canonical scalar ordering suitable for ordered keys.
    public var supportsOrderedIndex: Bool {
        !isArray && valuesHaveCanonicalOrdering
    }

    /// Whether the field is a scalar numeric value.
    public var isNumeric: Bool {
        guard !isArray else {
            return false
        }
        switch type {
        case .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64,
             .float32, .float64, .decimal:
            return true
        default:
            return false
        }
    }

    /// Whether the field has a deterministic equality and hash representation.
    public var supportsEqualityIndex: Bool {
        !isArray
    }
}
