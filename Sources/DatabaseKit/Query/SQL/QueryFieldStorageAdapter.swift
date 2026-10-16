import DatabaseTypes

/// Lossless adaptation selected exclusively by a declared query type.
public enum QueryFieldStorageAdapter {
    public static func encode(
        _ value: QueryValue, type: QueryColumnType, limits: QueryValueLimits
    ) throws(QueryValueError) -> FieldValue {
        try validateType(type)
        try QueryValueValidator.validate(value, type: type, limits: limits)
        var meter = QueryFieldStorageMeter(limits: limits)
        try meter.query(value, type: type, depth: 1)
        return try encodeValue(value, type: type)
    }

    public static func decode(
        _ payload: FieldValue, type: QueryColumnType, limits: QueryValueLimits
    ) throws(QueryValueError) -> QueryValue {
        try validateType(type)
        // Check the complete owned payload before allocating decoded collections.
        var meter = QueryFieldStorageMeter(limits: limits)
        try meter.field(payload, depth: 1)
        let decoded = try decodedFootprint(payload, type: type, limits: limits)
        try QueryValueFootprint(nodeCount: decoded.nodeCount,
                                collectionElementCount: decoded.collectionElementCount,
                                retainedByteCount: decoded.utf8ByteCount,
                                maximumNestingDepth: decoded.maximumNestingDepth).validate(limits: limits)
        let value = try decodeValue(payload, type: type, limits: limits)
        try QueryValueValidator.validate(value, type: type, limits: limits)
        return value
    }

    public static func measure(
        _ value: QueryValue, type: QueryColumnType
    ) throws(QueryValueError) -> QueryFieldStorageFootprint {
        try validateType(type)
        var meter = QueryFieldStorageMeter()
        try meter.query(value, type: type, depth: 1)
        return meter.footprint
    }

    public static func inferredLimits(
        for value: QueryValue, type: QueryColumnType
    ) throws(QueryValueError) -> QueryValueLimits {
        try validateType(type)
        var meter = QueryFieldStorageMeter()
        try meter.query(value, type: type, depth: 1)
        let envelope = try meter.inferredLimits()
        let source = try QueryValueValidator.measure(value)
        return mergedLimits(envelope, source: source)
    }

    public static func inferredLimits(
        for payload: FieldValue, type: QueryColumnType
    ) throws(QueryValueError) -> QueryValueLimits {
        try validateType(type)
        var meter = QueryFieldStorageMeter()
        try meter.field(payload, depth: 1)
        let envelope = try meter.inferredLimits()
        let decoded = try measureDecoded(payload, type: type)
        let minimum = try decoded.minimumJSONBStorageByteCount
        let allowance = try added(minimum, minimum)
        let bytes = try added(try added(envelope.maximumRetainedBytes, decoded.utf8ByteCount), allowance)
        return QueryValueLimits(maximumRetainedBytes: bytes,
                                maximumTotalNodes: max(envelope.maximumTotalNodes, decoded.nodeCount),
                                maximumNestingDepth: max(envelope.maximumNestingDepth, decoded.maximumNestingDepth),
                                maximumCollectionElements: max(envelope.maximumCollectionElements, decoded.collectionElementCount))
    }

    private static func mergedLimits(_ envelope: QueryValueLimits, source: QueryValueFootprint) -> QueryValueLimits {
        QueryValueLimits(maximumRetainedBytes: max(envelope.maximumRetainedBytes, source.retainedByteCount),
                         maximumTotalNodes: max(envelope.maximumTotalNodes, source.nodeCount),
                         maximumNestingDepth: max(envelope.maximumNestingDepth, source.maximumNestingDepth),
                         maximumCollectionElements: max(envelope.maximumCollectionElements, source.collectionElementCount))
    }

    public static func measureDecoded(
        _ payload: FieldValue, type: QueryColumnType
    ) throws(QueryValueError) -> QueryFieldDecodedFootprint {
        try decodedFootprint(payload, type: type, limits: nil)
    }

    private static func decodedFootprint(
        _ payload: FieldValue, type: QueryColumnType, limits: QueryValueLimits?
    ) throws(QueryValueError) -> QueryFieldDecodedFootprint {
        try validateType(type)
        var counts = QueryFieldDecodedFootprint()
        counts.nodeCount = 1
        counts.maximumNestingDepth = 1
        if case .null = payload { return counts }
        if case .sql(let sqlType) = type {
            switch sqlType {
            case .jsonb:
                let fields = try envelope(payload, kind: "jsonb", keys: ["nodes"])
                guard case .array(let records) = fields["nodes"] else { throw malformed() }
                var builder: QueryJSONBBuilder?
                return try walkPrefix(records, builder: &builder, limits: limits).0
            case .array:
                let fields = try envelope(payload, kind: "array", keys: ["dimensions", "elements"])
                guard case .array(let shape) = fields["dimensions"],
                      case .array(let cells) = fields["elements"],
                      case .array(let elementType) = sqlType else { throw malformed() }
                try validateShape(shape, cellCount: cells.count)
                counts.collectionElementCount = UInt64(cells.count)
                for cell in cells {
                    let child = try decodedFootprint(cell, type: .sql(elementType), limits: limits)
                    counts.nodeCount = try added(counts.nodeCount, child.nodeCount)
                    counts.collectionElementCount = try added(counts.collectionElementCount, child.collectionElementCount)
                    counts.maximumNestingDepth = max(counts.maximumNestingDepth, try added(child.maximumNestingDepth, 1))
                    counts.utf8ByteCount = try added(counts.utf8ByteCount, child.utf8ByteCount)
                    counts.jsonbNodeCount = try added(counts.jsonbNodeCount, child.jsonbNodeCount)
                    counts.jsonbElementIndexCount = try added(counts.jsonbElementIndexCount, child.jsonbElementIndexCount)
                    counts.jsonbMemberCount = try added(counts.jsonbMemberCount, child.jsonbMemberCount)
                }
                return counts
            case .json:
                let fields = try envelope(payload, kind: "json", keys: ["bytes"])
                guard case .bytes(let bytes) = fields["bytes"] else { throw malformed() }
                var meter = QueryFieldStorageMeter()
                try meter.field(payload, depth: 1)
                let parsed = try QueryJSONParser.validate(bytes: bytes, limits: meter.inferredLimits())
                counts.nodeCount = parsed.nodeCount
                counts.collectionElementCount = parsed.collectionElementCount
                counts.maximumNestingDepth = parsed.maximumNestingDepth
                counts.utf8ByteCount = UInt64(bytes.count)
                return counts
            case .decimal, .interval, .date, .time, .timestamp:
                let value = try decodeValue(payload, type: type, limits: QueryValueLimits(
                    maximumRetainedBytes: 0, maximumTotalNodes: 1,
                    maximumNestingDepth: 1, maximumCollectionElements: 0))
                guard QueryValueValidator.accepts(value, type: type) else { throw .incompatibleType }
                return counts
            default: break
            }
        }
        guard QueryValueValidator.accepts(.primitive(payload), type: type) else { throw .incompatibleType }
        var meter = QueryFieldStorageMeter()
        try meter.field(payload, depth: 1)
        counts.nodeCount = meter.footprint.valueNodes
        counts.collectionElementCount = try added(meter.footprint.objectEntries, meter.footprint.arrayElements)
        counts.maximumNestingDepth = meter.footprint.maximumDepth
        counts.utf8ByteCount = meter.footprint.newUTF8Bytes
        return counts
    }

    private static func validateShape(_ shape: [FieldValue], cellCount: Int) throws(QueryValueError) {
        guard shape.count <= 6 else { throw .invalidDimensionCount(shape.count) }
        var product: UInt64 = shape.isEmpty ? 0 : 1
        for dimension in shape {
            let fields = try exactObject(dimension, keys: ["lowerBound", "length"])
            guard case .int32(let lowerBound) = fields["lowerBound"],
                  case .int32(let length) = fields["length"] else { throw malformed() }
            _ = try QueryArrayDimension(lowerBound: lowerBound, length: length)
            let next = product.multipliedReportingOverflow(by: UInt64(length))
            guard !next.overflow else { throw .dimensionProductOverflow }
            product = next.partialValue
        }
        guard product == UInt64(cellCount) else {
            throw .elementCountMismatch(expected: product, actual: UInt64(cellCount))
        }
    }

    public static func validateDescriptor(
        _ type: QueryColumnType, fieldType: FieldSchemaType, isArray: Bool
    ) throws(QueryValueError) {
        try validateType(type)
        switch type {
        case .primitive(let expected, let expectedArray):
            guard fieldType == expected, isArray == expectedArray else { throw .invalidPersistenceDescriptor }
        case .sql(let sqlType):
            guard !isArray else { throw .invalidPersistenceDescriptor }
            let expected: FieldSchemaType
            switch sqlType {
            case .decimal, .json, .jsonb, .interval, .array: expected = .object
            case .boolean: expected = .bool
            case .smallint: expected = .int16
            case .integer: expected = .int32
            case .bigint: expected = .int64
            case .real: expected = .float32
            case .doublePrecision: expected = .float64
            case .char, .varchar, .text: expected = .string
            case .binary, .varbinary, .blob: expected = .bytes
            case .date: expected = .date
            case .time(false, _): expected = .time
            case .time(true, _): expected = .object
            case .timestamp(let withTimeZone, _): expected = withTimeZone ? .timestamp : .dateTime
            case .uuid: expected = .uuid
            case .custom: throw .invalidPersistenceDescriptor
            }
            guard fieldType == expected else { throw .invalidPersistenceDescriptor }
        }
    }

    private static func validateType(_ type: QueryColumnType) throws(QueryValueError) {
        guard case .sql(let type) = type else { return }
        try validateSQLType(type, allowsArray: true)
    }

    private static func validateSQLType(_ type: DataType, allowsArray: Bool) throws(QueryValueError) {
        guard QueryValueValidator.accepts(.primitive(.null), type: .sql(type)) else {
            throw .invalidPersistenceDescriptor
        }
        switch type {
        case .decimal(let precision, let scale):
            guard precision == nil || (1...38).contains(precision!),
                  scale == nil || (-1000...1000).contains(scale!) else { throw .invalidPersistenceDescriptor }
        case .char(let length), .varchar(let length), .binary(let length), .varbinary(let length):
            guard length == nil || length! > 0 else { throw .invalidPersistenceDescriptor }
        case .time(_, let precision), .timestamp(_, let precision):
            guard precision == nil || (0...6).contains(precision!) else { throw .invalidPersistenceDescriptor }
        case .array(let element):
            guard allowsArray else { throw .invalidPersistenceDescriptor }
            try validateSQLType(element, allowsArray: false)
        case .custom: throw .invalidPersistenceDescriptor
        default: break
        }
    }

    private static func encodeValue(
        _ value: QueryValue, type: QueryColumnType
    ) throws(QueryValueError) -> FieldValue {
        if case .primitive(.null) = value { return .null }
        switch (value, type) {
        case (.primitive(let value), _): return value
        case (.numeric(let number), .sql(.decimal)):
            return try object([("kind", .string("numeric")), ("value", .decimal(number.value)),
                               ("displayScale", .int32(number.displayScale))])
        case (.json(let json), .sql(.json)):
            return try object([("kind", .string("json")), ("bytes", .bytes(json.bytes))])
        case (.jsonb(let json), .sql(.jsonb)):
            return try object([("kind", .string("jsonb")), ("nodes", try encodeNode(json.root))])
        case (.interval(let interval), .sql(.interval)):
            return try object([("kind", .string("interval")),
                               ("months", .int32(Int32(interval.period.months))),
                               ("days", .int32(Int32(interval.period.days))),
                               ("microseconds", .int64(interval.microseconds))])
        case (.time(let time), .sql(.time(false, _))):
            return try object([("kind", .string("time")),
                               ("microseconds", .int64(time.microsecondsSinceMidnight))])
        case (.timeWithTimeZone(let time), .sql(.time(true, _))):
            return try object([("kind", .string("timeWithTimeZone")),
                               ("microseconds", .int64(time.time.microsecondsSinceMidnight)),
                               ("utcOffsetSeconds", .int32(time.utcOffsetSeconds))])
        case (.dateInfinity(let sign), .sql(.date)):
            return try object([("kind", .string("dateInfinity")), ("sign", .int8(sign == .negative ? -1 : 1))])
        case (.timestampInfinity(let sign, _), .sql(.timestamp)):
            return try object([("kind", .string("timestampInfinity")), ("sign", .int8(sign == .negative ? -1 : 1))])
        case (.intervalInfinity(let sign), .sql(.interval)):
            return try object([("kind", .string("intervalInfinity")), ("sign", .int8(sign == .negative ? -1 : 1))])
        case (.array(let array), .sql(.array(let elementType))):
            var dimensions: [FieldValue] = []
            dimensions.reserveCapacity(array.dimensions.count)
            for dimension in array.dimensions {
                dimensions.append(try object([("lowerBound", .int32(dimension.lowerBound)),
                                              ("length", .int32(dimension.length))]))
            }
            var elements: [FieldValue] = []
            elements.reserveCapacity(array.elements.count)
            for element in array.elements {
                elements.append(try encodeValue(element, type: .sql(elementType)))
            }
            return try object([("kind", .string("array")), ("dimensions", .array(dimensions)),
                               ("elements", .array(elements))])
        default: throw .incompatibleType
        }
    }

    private enum JSONBEncodingFrame {
        case node(QueryJSONBNode)
        case array(QueryJSONBElements, Int)
        case object(QueryJSONBMembers, Int)
    }

    private static func encodeNode(_ root: QueryJSONBNode) throws(QueryValueError) -> FieldValue {
        var records: [FieldValue] = []
        var work: [JSONBEncodingFrame] = [.node(root)]
        while let visit = work.popLast() {
            switch visit {
            case .node(let node):
                switch node {
                case .null: records.append(try object([("kind", .string("null"))]))
                case .bool(let value): records.append(try object([("kind", .string("bool")), ("value", .bool(value))]))
                case .string(let value): records.append(try object([("kind", .string("string")), ("value", .string(value))]))
                case .number(let value):
                    records.append(try object([("kind", .string("number")), ("value", .decimal(value.value)),
                                               ("displayScale", .int32(value.displayScale))]))
                case .array(let values):
                    records.append(try object([("kind", .string("array")), ("childCount", .uint64(UInt64(values.count)))]))
                    if !values.isEmpty { work.append(.array(values, 0)) }
                case .object(let values):
                    var keys: [FieldValue] = []
                    keys.reserveCapacity(values.count)
                    for member in values { keys.append(.string(member.key)) }
                    records.append(try object([("kind", .string("object")), ("keys", .array(keys))]))
                    if !values.isEmpty { work.append(.object(values, 0)) }
                }
            case .array(let values, let index):
                if index + 1 < values.count { work.append(.array(values, index + 1)) }
                work.append(.node(values[index]))
            case .object(let values, let index):
                if index + 1 < values.count { work.append(.object(values, index + 1)) }
                work.append(.node(values[index].value))
            }
        }
        return .array(records)
    }

    private static func decodeValue(
        _ payload: FieldValue, type: QueryColumnType, limits: QueryValueLimits
    ) throws(QueryValueError) -> QueryValue {
        if case .null = payload { return .primitive(.null) }
        guard case .sql(let sqlType) = type else { return .primitive(payload) }
        switch sqlType {
        case .date:
            if case .object = payload {
                return .dateInfinity(try decodeInfinity(payload, kind: "dateInfinity"))
            }
            return .primitive(payload)
        case .timestamp(let withTimeZone, _):
            if case .object = payload {
                return .timestampInfinity(try decodeInfinity(payload, kind: "timestampInfinity"),
                                          withTimeZone: withTimeZone)
            }
            return .primitive(payload)
        case .time(let withTimeZone, _):
            if !withTimeZone, case .time = payload { return .primitive(payload) }
            let fields = try envelope(payload, kind: withTimeZone ? "timeWithTimeZone" : "time",
                                      keys: withTimeZone ? ["microseconds", "utcOffsetSeconds"] : ["microseconds"])
            guard case .int64(let microseconds) = fields["microseconds"] else { throw malformed() }
            let time = try QueryTimeValue(microsecondsSinceMidnight: microseconds)
            if withTimeZone {
                guard case .int32(let offset) = fields["utcOffsetSeconds"] else { throw malformed() }
                return .timeWithTimeZone(QueryTimeWithTimeZoneValue(time: time, utcOffsetSeconds: offset))
            }
            return .time(time)
        case .decimal:
            let fields = try envelope(payload, kind: "numeric", keys: ["value", "displayScale"])
            guard case .decimal(let value) = fields["value"],
                  case .int32(let scale) = fields["displayScale"] else { throw malformed() }
            return .numeric(try QueryNumericValue(value: value, displayScale: scale))
        case .json:
            let fields = try envelope(payload, kind: "json", keys: ["bytes"])
            guard case .bytes(let bytes) = fields["bytes"] else { throw malformed() }
            return .json(try QueryJSONValue(bytes: bytes, limits: limits))
        case .jsonb:
            let fields = try envelope(payload, kind: "jsonb", keys: ["nodes"])
            guard case .array(let records) = fields["nodes"] else { throw malformed() }
            return .jsonb(try QueryJSONBValue(root: decodeNode(records, limits: limits), limits: limits))
        case .interval:
            if case .object(let fields) = payload,
               fields["kind"] == .string("intervalInfinity") {
                return .intervalInfinity(try decodeInfinity(payload, kind: "intervalInfinity"))
            }
            let fields = try envelope(payload, kind: "interval", keys: ["months", "days", "microseconds"])
            guard case .int32(let months) = fields["months"], case .int32(let days) = fields["days"],
                  case .int64(let microseconds) = fields["microseconds"] else { throw malformed() }
            var seconds = microseconds / 1_000_000
            var remainder = microseconds % 1_000_000
            if remainder < 0 { seconds -= 1; remainder += 1_000_000 }
            let time: TimeSpan
            do { time = try TimeSpan(seconds: seconds, nanoseconds: UInt32(remainder) * 1_000) }
            catch { throw .arithmeticOverflow }
            return .interval(try QueryIntervalValue(period: CalendarPeriod(months: Int64(months), days: Int64(days)), time: time))
        case .array(let elementType):
            let fields = try envelope(payload, kind: "array", keys: ["dimensions", "elements"])
            guard case .array(let shape) = fields["dimensions"],
                  case .array(let cells) = fields["elements"] else { throw malformed() }
            try validateShape(shape, cellCount: cells.count)
            var dimensions: [QueryArrayDimension] = []
            dimensions.reserveCapacity(shape.count)
            for dimension in shape {
                let fields = try exactObject(dimension, keys: ["lowerBound", "length"])
                guard case .int32(let lowerBound) = fields["lowerBound"],
                      case .int32(let length) = fields["length"] else { throw malformed() }
                dimensions.append(try QueryArrayDimension(lowerBound: lowerBound, length: length))
            }
            var elements: [QueryValue] = []
            elements.reserveCapacity(cells.count)
            for cell in cells { elements.append(try decodeValue(cell, type: .sql(elementType), limits: limits)) }
            return .array(try QueryArrayValue(elementType: elementType, dimensions: dimensions, elements: elements, limits: limits))
        default: return .primitive(payload)
        }
    }

    private enum JSONBDecodingFrame {
        case array(Int, Int, [Int])
        case object([FieldValue], Int, [QueryJSONBIndexedMember])
    }

    private static func decodeNode(_ records: [FieldValue], limits: QueryValueLimits) throws(QueryValueError) -> QueryJSONBNode {
        var builder: QueryJSONBBuilder? = QueryJSONBBuilder(limits: limits)
        let (_, root) = try walkPrefix(records, builder: &builder, limits: limits)
        guard let root, let builder else { throw malformed() }
        return try builder.finish(root: root)
    }

    private static func walkPrefix(
        _ records: [FieldValue], builder: inout QueryJSONBBuilder?, limits: QueryValueLimits?
    ) throws(QueryValueError) -> (QueryFieldDecodedFootprint, Int?) {
        guard !records.isEmpty else { throw malformed() }
        var counts = QueryFieldDecodedFootprint()
        var parents: [JSONBDecodingFrame] = []
        nextRecord: for (index, record) in records.enumerated() {
            counts.nodeCount = try added(counts.nodeCount, 1)
            counts.jsonbNodeCount = counts.nodeCount
            counts.maximumNestingDepth = max(counts.maximumNestingDepth, UInt64(parents.count) + 1)
            try validateDecodedCounts(counts, limits: limits)
            guard case .object(let fields) = record, case .string(let kind) = fields["kind"] else { throw malformed() }
            var completed: Int?
            switch kind {
            case "null":
                _ = try envelope(record, kind: kind, keys: [])
                completed = try builder?.append(.null)
            case "bool":
                _ = try envelope(record, kind: kind, keys: ["value"])
                guard case .bool(let value) = fields["value"] else { throw malformed() }
                completed = try builder?.append(.bool(value))
            case "string":
                _ = try envelope(record, kind: kind, keys: ["value"])
                guard case .string(let value) = fields["value"] else { throw malformed() }
                try admitJSONBString(value, counts: &counts)
                completed = try builder?.append(.string(value))
            case "number":
                _ = try envelope(record, kind: kind, keys: ["value", "displayScale"])
                guard case .decimal(let value) = fields["value"],
                      case .int32(let scale) = fields["displayScale"] else { throw malformed() }
                let number = try QueryNumericValue(value: value, displayScale: scale)
                completed = try builder?.append(.number(number))
            case "array":
                _ = try envelope(record, kind: kind, keys: ["childCount"])
                guard case .uint64(let count) = fields["childCount"],
                      count <= UInt64(records.count - index - 1), let count = Int(exactly: count) else { throw malformed() }
                counts.collectionElementCount = try added(counts.collectionElementCount, UInt64(count))
                counts.jsonbElementIndexCount = try added(counts.jsonbElementIndexCount, UInt64(count))
                try validateDecodedCounts(counts, limits: limits)
                if count > 0 {
                    var ids: [Int] = []
                    if builder != nil { ids.reserveCapacity(count) }
                    parents.append(.array(count, 0, ids))
                    continue nextRecord
                }
                completed = try builder?.appendArray([])
            case "object":
                _ = try envelope(record, kind: kind, keys: ["keys"])
                guard case .array(let keys) = fields["keys"],
                      keys.count <= records.count - index - 1 else { throw malformed() }
                var previous: String?
                for key in keys {
                    guard case .string(let key) = key else { throw malformed() }
                    if let previous, QueryJSONParser.compareKeys(previous, key) >= 0 { throw .nonCanonicalJSONB }
                    try admitJSONBString(key, counts: &counts)
                    previous = key
                }
                counts.collectionElementCount = try added(counts.collectionElementCount, UInt64(keys.count))
                counts.jsonbMemberCount = try added(counts.jsonbMemberCount, UInt64(keys.count))
                try validateDecodedCounts(counts, limits: limits)
                if !keys.isEmpty {
                    var ids: [QueryJSONBIndexedMember] = []
                    if builder != nil { ids.reserveCapacity(keys.count) }
                    parents.append(.object(keys, 0, ids))
                    continue nextRecord
                }
                completed = try builder?.appendObject([])
            default: throw malformed()
            }
            try validateDecodedCounts(counts, limits: limits)
            while let parent = parents.popLast() {
                switch consume parent {
                case .array(let count, let index, var ids):
                    if let completed { ids.append(completed) }
                    if index + 1 < count {
                        parents.append(.array(count, index + 1, ids))
                        continue nextRecord
                    }
                    completed = try builder?.appendArray(ids)
                case .object(let keys, let index, var ids):
                    guard case .string(let key) = keys[index] else { throw malformed() }
                    if let completed { ids.append(QueryJSONBIndexedMember(key: key, value: completed)) }
                    if index + 1 < keys.count {
                        parents.append(.object(keys, index + 1, ids))
                        continue nextRecord
                    }
                    completed = try builder?.appendObject(ids)
                }
            }
            guard index + 1 == records.count else { throw malformed() }
            return (counts, completed)
        }
        throw malformed()
    }

    private static func validateDecodedCounts(_ counts: QueryFieldDecodedFootprint, limits: QueryValueLimits?) throws(QueryValueError) {
        guard let limits else { return }
        try QueryValueFootprint(nodeCount: counts.nodeCount,
                                collectionElementCount: counts.collectionElementCount,
                                retainedByteCount: counts.utf8ByteCount,
                                maximumNestingDepth: counts.maximumNestingDepth).validate(limits: limits)
    }

    private static func admitJSONBString(_ value: String, counts: inout QueryFieldDecodedFootprint) throws(QueryValueError) {
        guard !value.unicodeScalars.contains(where: { $0.value == 0 }) else { throw .nonCanonicalJSONB }
        counts.utf8ByteCount = try added(counts.utf8ByteCount, UInt64(value.utf8.count))
    }

    private static func added(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw .arithmeticOverflow }
        return result.partialValue
    }

    private static func object(_ fields: [(key: String, value: FieldValue)]) throws(QueryValueError) -> FieldValue {
        do { return .object(try FieldObject(fields)) }
        catch { throw malformed() }
    }

    private static func exactObject(_ payload: FieldValue, keys: [String]) throws(QueryValueError) -> FieldObject {
        guard case .object(let fields) = payload, fields.count == keys.count else { throw malformed() }
        for key in keys { guard fields[key] != nil else { throw malformed() } }
        return fields
    }

    private static func envelope(_ payload: FieldValue, kind: String, keys: [String]) throws(QueryValueError) -> FieldObject {
        guard case .object(let fields) = payload, fields.count == keys.count + 1,
              case .string(let actualKind) = fields["kind"], actualKind == kind else { throw malformed() }
        for key in keys { guard fields[key] != nil else { throw malformed() } }
        return fields
    }

    private static func malformed() -> QueryValueError {
        .invalidPersistencePayload(reason: "Invalid declared field envelope")
    }

    private static func decodeInfinity(_ payload: FieldValue, kind: String) throws(QueryValueError)
        -> QueryTemporalInfinity {
        let fields = try envelope(payload, kind: kind, keys: ["sign"])
        guard case .int8(let sign) = fields["sign"] else { throw malformed() }
        switch sign {
        case -1: return .negative
        case 1: return .positive
        default: throw malformed()
        }
    }
}
