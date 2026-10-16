import DatabaseTypes

/// All SQL collection edges are indices into this immutable owner.
final class QueryValueStorage: Sendable {
    enum Kind: Sendable {
        case primitive(FieldValue)
        case numeric(QueryNumericValue)
        case json(QueryJSONValue)
        case jsonb(QueryJSONBValue)
        case interval(QueryIntervalValue)
        case time(QueryTimeValue)
        case timeWithTimeZone(QueryTimeWithTimeZoneValue)
        case dateInfinity(QueryTemporalInfinity)
        case timestampInfinity(QueryTemporalInfinity, Bool)
        case intervalInfinity(QueryTemporalInfinity)
        case array(type: Int, dimensions: Range<Int>, elements: Range<Int>)
        case composite(type: Int, fields: Range<Int>)
    }

    struct Record: Sendable {
        let kind: Kind
        let logical: QueryValueFootprint
    }

    let records: [Record]
    let children: [Int]
    let dimensions: [QueryArrayDimension]
    let types: QueryTypeStorage
    let footprint: QueryValueStorageFootprint

    init(records: [Record], children: [Int], dimensions: [QueryArrayDimension],
         types: QueryTypeStorage, footprint: QueryValueStorageFootprint) {
        self.records = records; self.children = children; self.dimensions = dimensions
        self.types = types; self.footprint = footprint
    }

    func value(at index: Int) -> QueryValue {
        switch records[index].kind {
        case .primitive(let x): .primitive(x)
        case .numeric(let x): .numeric(x)
        case .json(let x): .json(x)
        case .jsonb(let x): .jsonb(x)
        case .interval(let x): .interval(x)
        case .time(let x): .time(x)
        case .timeWithTimeZone(let x): .timeWithTimeZone(x)
        case .dateInfinity(let x): .dateInfinity(x)
        case .timestampInfinity(let x, let zone): .timestampInfinity(x, withTimeZone: zone)
        case .intervalInfinity(let x): .intervalInfinity(x)
        case .array: .array(QueryArrayValue(storage: self, index: index))
        case .composite: .composite(QueryCompositeValue(storage: self, index: index))
        }
    }

    func measure(_ index: Int) throws(QueryValueError) -> QueryValueFootprint {
        let logical = records[index].logical
        return QueryValueFootprint(nodeCount: logical.nodeCount,
            collectionElementCount: logical.collectionElementCount,
            retainedByteCount: try footprint.retainedByteCount,
            maximumNestingDepth: logical.maximumNestingDepth)
    }
}
