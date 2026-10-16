import DatabaseTypes

/// Measures the destination shape with a depth-bounded temporary worklist.
internal struct QueryFieldStorageMeter {
    var footprint = QueryFieldStorageFootprint()
    private(set) var retainedByteCount: UInt64 = 0
    private let limits: QueryValueLimits?

    init(limits: QueryValueLimits? = nil) { self.limits = limits }

    private enum Visit {
        case query(QueryValue, QueryColumnType, UInt64)
        case jsonNode(QueryJSONBNode, UInt64)
        case field(FieldValue, UInt64)
        case identifier(ReferenceIdentifier, UInt64)
        case term(DatabaseTypes.RDFTerm, UInt64)
        case fieldArray([FieldValue], Int, UInt64)
        case fields(FieldObject, Int, UInt64)
        case queryArray([QueryValue], DataType, Int, UInt64)
        case jsonArray(QueryJSONBElements, Int, UInt64)
        case jsonMembers(QueryJSONBMembers, Int, UInt64)
        case identifiers([ReferenceIdentifier], Int, UInt64)
        case partitions(FieldObject, UInt64)
    }

    mutating func query(_ value: QueryValue, type: QueryColumnType, depth: UInt64) throws(QueryValueError) {
        try traverse(.query(value, type, depth), depth: depth)
    }

    mutating func jsonNode(_ value: QueryJSONBNode, depth: UInt64) throws(QueryValueError) {
        try traverse(.jsonNode(value, depth), depth: depth)
    }

    mutating func field(_ value: FieldValue, depth: UInt64) throws(QueryValueError) {
        try traverse(.field(value, depth), depth: depth)
    }

    private mutating func traverse(_ initial: Visit, depth: UInt64) throws(QueryValueError) {
        try checkNextNode(depth)
        var work = [initial]
        while let visit = work.popLast() {
            switch visit {
            case .query(let value, let type, let depth):
                guard QueryValueValidator.accepts(value, type: type) else { throw .incompatibleType }
                if case .primitive(let primitive) = value {
                    if !value.isNull, case .sql(let sqlType) = type {
                        switch sqlType {
                        case .decimal, .json, .jsonb, .array, .interval: throw .incompatibleType
                        default: break
                        }
                    }
                    try schedule(.field(primitive, depth), depth: depth, work: &work)
                    continue
                }
                switch (value, type) {
                case (.numeric, .sql(.decimal)):
                    try envelope("numeric", keys: ("value", "displayScale", nil), depth: depth)
                    let childDepth = try Self.sum(depth, 1)
                    try node(childDepth); try node(childDepth)
                case (.json(let json), .sql(.json)):
                    try envelope("json", keys: ("bytes", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                    try bytes(json.bytes)
                case (.jsonb(let json), .sql(.jsonb)):
                    try envelope("jsonb", keys: ("nodes", nil, nil), depth: depth)
                    let count = try json.measure().nodeCount
                    guard let count = Int(exactly: count) else { throw .arithmeticOverflow }
                    try collection(count, depth: Self.sum(depth, 1))
                    let recordDepth = try Self.sum(depth, 2)
                    try schedule(.jsonNode(json.root, recordDepth), depth: recordDepth, work: &work)
                case (.interval, .sql(.interval)):
                    try envelope("interval", keys: ("months", "days", "microseconds"), depth: depth)
                    let childDepth = try Self.sum(depth, 1)
                    try node(childDepth); try node(childDepth); try node(childDepth)
                case (.time, .sql(.time(false, _))):
                    try envelope("time", keys: ("microseconds", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                case (.timeWithTimeZone, .sql(.time(true, _))):
                    try envelope("timeWithTimeZone", keys: ("microseconds", "utcOffsetSeconds", nil), depth: depth)
                    let childDepth = try Self.sum(depth, 1)
                    try node(childDepth); try node(childDepth)
                case (.dateInfinity, .sql(.date)):
                    try envelope("dateInfinity", keys: ("sign", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                case (.timestampInfinity, .sql(.timestamp)):
                    try envelope("timestampInfinity", keys: ("sign", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                case (.intervalInfinity, .sql(.interval)):
                    try envelope("intervalInfinity", keys: ("sign", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                case (.array(let array), .sql(.array(let elementType))):
                    guard array.elementType == elementType else { throw .incompatibleType }
                    try envelope("array", keys: ("dimensions", "elements", nil), depth: depth)
                    try collection(array.dimensions.count, depth: Self.sum(depth, 1))
                    for _ in array.dimensions {
                        try object(keys: ("lowerBound", "length"), depth: Self.sum(depth, 2))
                        let childDepth = try Self.sum(depth, 3)
                        try node(childDepth); try node(childDepth)
                    }
                    try collection(array.elements.count, depth: Self.sum(depth, 1))
                    if !array.elements.isEmpty {
                        let childDepth = try Self.sum(depth, 2)
                        try schedule(.queryArray(array.elements, elementType, 0, childDepth), depth: childDepth, work: &work)
                    }
                default: throw .incompatibleType
                }
            case .jsonNode(let value, let depth):
                switch value {
                case .null: try envelope("null", keys: (nil, nil, nil), depth: depth)
                case .bool:
                    try envelope("bool", keys: ("value", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                case .string(let value):
                    try envelope("string", keys: ("value", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                    try text(value)
                case .number:
                    try envelope("number", keys: ("value", "displayScale", nil), depth: depth)
                    let childDepth = try Self.sum(depth, 1)
                    try node(childDepth); try node(childDepth)
                case .array(let values):
                    try envelope("array", keys: ("childCount", nil, nil), depth: depth)
                    try node(try Self.sum(depth, 1))
                    if !values.isEmpty { try schedule(.jsonArray(values, 0, depth), depth: depth, work: &work) }
                case .object(let values):
                    try envelope("object", keys: ("keys", nil, nil), depth: depth)
                    try collection(values.count, depth: Self.sum(depth, 1))
                    for member in values {
                        try node(try Self.sum(depth, 2))
                        try text(member.key)
                    }
                    if !values.isEmpty { try schedule(.jsonMembers(values, 0, depth), depth: depth, work: &work) }
                }
            case .field(let value, let depth):
                try node(depth)
                switch value {
                case .array(let values):
                    try Self.add(UInt64(values.count), to: &footprint.arrayElements)
                    try checkCollection()
                    if !values.isEmpty {
                        let childDepth = try Self.sum(depth, 1)
                        try schedule(.fieldArray(values, 0, childDepth), depth: childDepth, work: &work)
                    }
                case .object(let values):
                    try beginFields(values, depth: depth, work: &work)
                case .string(let value): try text(value)
                case .bytes(let value): try bytes(value)
                case .vector(let value):
                    guard let capacity = value.retainedByteCount else { throw .unknownRetainedByteCount }
                    let width: UInt64
                    switch value.elementType {
                    case .int8, .uint8: width = 1
                    case .int16, .uint16: width = 2
                    case .int32, .uint32, .float32: width = 4
                    case .int64, .uint64, .float64: width = 8
                    }
                    let length = UInt64(value.count).multipliedReportingOverflow(by: width)
                    guard !length.overflow else { throw .arithmeticOverflow }
                    try retained(length: length.partialValue, capacity: UInt64(capacity))
                case .reference(let value):
                    try text(value.entity)
                    let childDepth = try Self.sum(depth, 1)
                    try checkNextNode(childDepth)
                    work.append(.partitions(value.partitions, childDepth))
                    work.append(.identifier(value.id, childDepth))
                case .rdfTerm(let value):
                    let childDepth = try Self.sum(depth, 1)
                    try schedule(.term(value, childDepth), depth: childDepth, work: &work)
                default: break
                }
            case .identifier(let value, let depth):
                try node(depth)
                switch value {
                case .string(let value): try text(value)
                case .bytes(let value): try bytes(value)
                case .composite(let values):
                    try Self.add(UInt64(values.count), to: &footprint.arrayElements)
                    try checkCollection()
                    if !values.isEmpty {
                        let childDepth = try Self.sum(depth, 1)
                        try schedule(.identifiers(values, 0, childDepth), depth: childDepth, work: &work)
                    }
                default: break
                }
            case .term(let value, let depth):
                try node(depth)
                switch value {
                case .iri(let value): try text(value.rawValue)
                case .blankNode(let value): try text(value.rawValue)
                case .literal(let value):
                    try text(value.lexicalForm)
                    try text(value.datatypeIRI.rawValue)
                    if let language = value.languageTag { try text(language.rawValue) }
                case .tripleTerm(let subject, let predicate, let object):
                    switch subject {
                    case .iri(let value): try text(value.rawValue)
                    case .blankNode(let value): try text(value.rawValue)
                    }
                    try text(predicate.rawValue)
                    let childDepth = try Self.sum(depth, 1)
                    try schedule(.term(object, childDepth), depth: childDepth, work: &work)
                }
            case .fieldArray(let values, let index, let depth):
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.fieldArray(values, index + 1, depth)) }
                work.append(.field(values[index], depth))
            case .fields(let values, let index, let depth):
                let entry = values.fields[index]
                try text(entry.key)
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.fields(values, index + 1, depth)) }
                work.append(.field(entry.value, depth))
            case .queryArray(let values, let type, let index, let depth):
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.queryArray(values, type, index + 1, depth)) }
                work.append(.query(values[index], .sql(type), depth))
            case .jsonArray(let values, let index, let depth):
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.jsonArray(values, index + 1, depth)) }
                work.append(.jsonNode(values[index], depth))
            case .jsonMembers(let values, let index, let depth):
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.jsonMembers(values, index + 1, depth)) }
                work.append(.jsonNode(values[index].value, depth))
            case .identifiers(let values, let index, let depth):
                try checkNextNode(depth)
                if index + 1 < values.count { work.append(.identifiers(values, index + 1, depth)) }
                work.append(.identifier(values[index], depth))
            case .partitions(let values, let depth):
                try node(depth)
                try beginFields(values, depth: depth, work: &work)
            }
        }
    }

    private func checkNextNode(_ depth: UInt64) throws(QueryValueError) {
        if let limits {
            try Self.check("totalNodes", Self.sum(footprint.valueNodes, 1), limits.maximumTotalNodes)
            try Self.check("depth", depth, limits.maximumNestingDepth)
        }
    }

    private func schedule(_ visit: Visit, depth: UInt64, work: inout [Visit]) throws(QueryValueError) {
        try checkNextNode(depth)
        work.append(visit)
    }

    private mutating func beginFields(_ values: FieldObject, depth: UInt64, work: inout [Visit]) throws(QueryValueError) {
        try Self.add(UInt64(values.count), to: &footprint.objectEntries)
        try checkCollection()
        if !values.isEmpty {
            let childDepth = try Self.sum(depth, 1)
            try schedule(.fields(values, 0, childDepth), depth: childDepth, work: &work)
        }
    }

    private mutating func bytes(_ value: ByteString) throws(QueryValueError) {
        guard let capacity = value.retainedByteCount else { throw .unknownRetainedByteCount }
        try retained(length: UInt64(value.count), capacity: UInt64(capacity))
    }

    private mutating func node(_ depth: UInt64) throws(QueryValueError) {
        try Self.add(1, to: &footprint.valueNodes)
        footprint.maximumDepth = max(footprint.maximumDepth, depth)
        if let limits {
            try Self.check("totalNodes", footprint.valueNodes, limits.maximumTotalNodes)
            try Self.check("depth", depth, limits.maximumNestingDepth)
        }
    }

    private mutating func text(_ value: String) throws(QueryValueError) {
        try utf8(UInt64(value.utf8.count))
    }

    private mutating func utf8(_ count: UInt64) throws(QueryValueError) {
        try Self.add(count, to: &footprint.newUTF8Bytes)
        try Self.add(count, to: &retainedByteCount)
        try checkBytes()
    }

    private mutating func retained(length: UInt64, capacity: UInt64) throws(QueryValueError) {
        try Self.add(1, to: &footprint.retainedByteViewCount)
        try Self.add(length, to: &footprint.retainedByteViewLength)
        try Self.add(capacity, to: &retainedByteCount)
        try checkBytes()
    }

    private mutating func collection(_ count: Int, depth: UInt64) throws(QueryValueError) {
        try node(depth)
        try Self.add(UInt64(count), to: &footprint.arrayElements)
        try checkCollection()
    }

    private mutating func object(keys: (StaticString, StaticString), depth: UInt64) throws(QueryValueError) {
        try node(depth)
        try Self.add(2, to: &footprint.objectEntries)
        try checkCollection()
        try utf8(UInt64(keys.0.utf8CodeUnitCount + keys.1.utf8CodeUnitCount))
    }

    private mutating func envelope(_ kind: StaticString, keys: (StaticString?, StaticString?, StaticString?), depth: UInt64) throws(QueryValueError) {
        try node(depth)
        var count: UInt64 = 1
        var bytes: UInt64 = 4 + UInt64(kind.utf8CodeUnitCount)
        if let key = keys.0 { count += 1; bytes += UInt64(key.utf8CodeUnitCount) }
        if let key = keys.1 { count += 1; bytes += UInt64(key.utf8CodeUnitCount) }
        if let key = keys.2 { count += 1; bytes += UInt64(key.utf8CodeUnitCount) }
        try Self.add(count, to: &footprint.objectEntries)
        try checkCollection()
        try utf8(bytes)
        try node((try Self.sum(depth, 1)))
    }

    func inferredLimits() throws(QueryValueError) -> QueryValueLimits {
        // Lexical JSON's byte length bounds its possible nodes/depth without parsing.
        let bytes = retainedByteCount
        let nodes = try Self.sum(footprint.valueNodes, bytes)
        let collections = try Self.sum(try Self.sum(footprint.arrayElements, footprint.objectEntries), bytes)
        return QueryValueLimits(maximumRetainedBytes: bytes, maximumTotalNodes: nodes,
                                maximumNestingDepth: max(footprint.maximumDepth, bytes),
                                maximumCollectionElements: collections)
    }

    private func checkBytes() throws(QueryValueError) {
        if let limits { try Self.check("retainedBytes", retainedByteCount, limits.maximumRetainedBytes) }
    }

    private func checkCollection() throws(QueryValueError) {
        if let limits {
            try Self.check("collectionElements", try Self.sum(footprint.arrayElements, footprint.objectEntries), limits.maximumCollectionElements)
        }
    }

    private static func check(_ resource: String, _ actual: UInt64, _ maximum: UInt64) throws(QueryValueError) {
        guard actual <= maximum else { throw .resourceLimit(resource: resource, actual: actual, maximum: maximum) }
    }

    private static func sum(_ lhs: UInt64, _ rhs: UInt64) throws(QueryValueError) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        guard !result.overflow else { throw .arithmeticOverflow }
        return result.partialValue
    }

    private static func add(_ value: UInt64, to total: inout UInt64) throws(QueryValueError) {
        total = try Self.sum(total, value)
    }
}
