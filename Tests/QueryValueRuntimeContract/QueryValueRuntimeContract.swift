import DatabaseKit
import DatabaseTypes
import DatabaseWire
#if canImport(WASILibc)
import WASILibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A bounded synchronous executable fixture, without a testing runtime dependency.
@main
struct QueryValueRuntimeContract {
    private enum Failure: Error {
        case assertion(UInt8)
        case query(QueryValueError)
        case wire(DatabaseWireError)
        case time(TimeSpanError)
        case wireLimits(DatabaseWireLimitsError)
        case structure(QueryStructuralValidationError)
        case binding(QueryParameterBindingError)
    }

    private static let limits = QueryValueLimits(
        maximumRetainedBytes: 4_000_000, maximumTotalNodes: 20_000,
        maximumNestingDepth: 5_000, maximumCollectionElements: 20_000
    )

    static func main() {
        print("QUERY_VALUE_RUNTIME_BEGIN")
        do {
            try run()
            print("QUERY_VALUE_RUNTIME_PASS cases=8")
        } catch {
            switch error {
            case .assertion(let code): print("QUERY_VALUE_RUNTIME_FAIL assertion=\(code)")
            case .query: print("QUERY_VALUE_RUNTIME_FAIL query")
            case .wire: print("QUERY_VALUE_RUNTIME_FAIL wire")
            case .time: print("QUERY_VALUE_RUNTIME_FAIL time")
            case .wireLimits: print("QUERY_VALUE_RUNTIME_FAIL wire-limits")
            case .structure: print("QUERY_VALUE_RUNTIME_FAIL structure")
            case .binding: print("QUERY_VALUE_RUNTIME_FAIL binding")
            }
            exit(1)
        }
    }

    private static func run() throws(Failure) {
        let time: TimeSpan
        do { time = try TimeSpan(seconds: -1, nanoseconds: 999_999_000) }
        catch { throw .time(error) }
        let values = try query { () throws(QueryValueError) in try richValues(time: time) }
        let types: [QueryColumnType] = [
            .sql(.decimal(precision: nil, scale: nil)), .sql(.json), .sql(.jsonb),
            .sql(.array(.integer)), .sql(.interval),
        ]
        try require(values.count == 5, code: 1)
        guard case .numeric(let numeric) = values[0], case .json(let json) = values[1],
              case .jsonb(let jsonb) = values[2], case .array(let array) = values[3],
              case .interval(let interval) = values[4] else { throw .assertion(2) }
        try require(numeric.displayScale == 6 && json.bytes == ByteString(utf8: " {\"b\":1.00,\"a\":null,\"b\":2.000,\"é\":\"😀\"} "), code: 3)
        try require(array.dimensions[0].lowerBound == -2 && array.elements[1] == .primitive(.null), code: 4)
        try require(interval.period.months == 5 && interval.period.days == -7 && interval.microseconds == -1, code: 5)
        guard case .object(let members) = jsonb.root, members.count == 3,
              members[0].key == "a", members[1].key == "b",
              members[2].key == "é", case .string(let unicode) = members[2].value,
              unicode.utf8.elementsEqual("😀".utf8),
              case .number(let number) = members[1].value else { throw .assertion(6) }
        try require(number.displayScale == 3, code: 7)
        let families = ["numeric", "json", "jsonb", "array", "interval"]
        for (index, value) in values.enumerated() {
            try require(Literal.queryValue(value, type: types[index]).description
                        == "queryValue(\(families[index]), type: sql)", code: 31)
            try require(Literal.queryValue(value).description
                        == "queryValue(\(families[index]), type: inferred)", code: 32)
        }
        try require(Literal.queryValue(.primitive(.null), type: .primitive(.int64)).description
                    == "queryValue(primitive, type: primitive)", code: 33)
        pass("rich-values")

        for (value, type) in zip(values, types) {
            let payload = try query { () throws(QueryValueError) in
                try QueryFieldStorageAdapter.encode(value, type: type, limits: limits)
            }
            let restored = try query { () throws(QueryValueError) in
                try QueryFieldStorageAdapter.decode(payload, type: type, limits: limits)
            }
            try require(restored == value, code: 8)
        }
        pass("persistence")
        try deepJSONBLifecycle()
        pass("deep-jsonb")
        var columns: [QueryColumn] = []
        for (index, type) in types.enumerated() {
            columns.append(try query { () throws(QueryValueError) in
                try QueryColumn(number: UInt32(index + 1), name: "value", type: type, isNullable: false)
            })
        }
        let expected = QueryRow(values: values)
        let retained = try retainedPage(columns: columns, rows: [expected])
        try require(retained.columns == columns && retained.rowCount == 1, code: 9)
        var iterator = retained.makeRowIterator()
        let restored = try wire { () throws(DatabaseWireError) in try iterator.next() }
        try require(restored == expected, code: 10)
        try require(try wire { () throws(DatabaseWireError) in try iterator.next() } == nil, code: 11)
        let empty = try retainedPage(columns: columns, rows: [])
        try require(empty.columns == columns && empty.rowCount == 0, code: 12)
        try require(try wire { () throws(DatabaseWireError) in try empty.materializedRows(maximumCount: 0) }.isEmpty, code: 13)
        pass("typed-pages")
        try typedParameter(value: values[0])
        pass("typed-parameters")
        try invalidValues(deepRoot: jsonb.root)
        pass("invalid-values")
        try wireFailures(columns: columns, row: expected)
        pass("wire-errors")
        try sqlConstructorsAndTemporalDescriptors()
        pass("sql-constructors-temporal-descriptors")
    }

    private static func richValues(time: TimeSpan) throws(QueryValueError) -> [QueryValue] {
        let numeric = try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 2), displayScale: 6)
        let json = try QueryJSONValue(bytes: ByteString(utf8: " {\"b\":1.00,\"a\":null,\"b\":2.000,\"é\":\"😀\"} "), limits: limits)
        let jsonb = try QueryJSONBValue(json: json, limits: limits)
        let array = try QueryArrayValue(elementType: .integer,
            dimensions: [QueryArrayDimension(lowerBound: -2, length: 2)],
            elements: [.primitive(.int32(7)), .primitive(.null)], limits: limits)
        let interval = try QueryIntervalValue(period: CalendarPeriod(months: 5, days: -7), time: time)
        return [.numeric(numeric), .json(json), .jsonb(jsonb), .array(array), .interval(interval)]
    }

    private static func retainedPage(columns: [QueryColumn], rows: [QueryRow]) throws(Failure) -> QueryRowPage {
        let page = try makePage(columns: columns, rows: rows, snapshotVersion: 9)
        let frame = try wire { () throws(DatabaseWireError) in
            try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 17, response: .rows(page))
        }
        let response = try wire { () throws(DatabaseWireError) in
            try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 17)
        }
        guard case .success(.rows(let decoded)) = response else { throw .assertion(14) }
        return decoded
    }

    private static func makePage(columns: [QueryColumn], rows: [QueryRow],
                                 snapshotVersion: UInt64? = nil) throws(Failure) -> QueryRowPage {
        #if DATABASE_KIT_MULTI_BASE
        let point: DomainReadPoint
        do {
            point = try DomainReadPoint(domainID: "query-value-runtime", position: .version(snapshotVersion ?? 1))
        } catch { throw .wire(.invalidBaseIdentifier(error)) }
        return try wire { () throws(DatabaseWireError) in
            try QueryRowPage(columns: columns, rows: rows, provenance: nil, consistency: .transactional(point))
        }
        #else
        return try wire { () throws(DatabaseWireError) in
            try QueryRowPage(columns: columns, rows: rows, snapshotVersion: snapshotVersion)
        }
        #endif
    }

    private static func typedParameter(value: QueryValue) throws(Failure) {
        let parameter = QueryParameter(position: 1, name: "amount", value: value,
                                        type: .sql(.decimal(precision: 10, scale: 6)))
        let null = QueryParameter(position: 2, name: "missing", value: .primitive(.null), type: .sql(.jsonb))
        let request = QueryExecuteOperation.Request(input: .text(language: .sql, statement: "SELECT $1, $2"), parameters: [parameter, null])
        let frame = try wire { () throws(DatabaseWireError) in
            #if DATABASE_KIT_MULTI_BASE
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 18,
                                                     target: .database, request: request)
            #else
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 18, request: request)
            #endif
        }
        let decoded = try wire { () throws(DatabaseWireError) in
            try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame)
        }
        try require(decoded.request.parameters == [parameter, null], code: 15)
    }

    private static func deepJSONBLifecycle() throws(Failure) {
        // One parser-built arena preserves the actual depth-4096 destruction counterexample.
        let text = String(repeating: "[", count: 4_095) + "1.230000" + String(repeating: "]", count: 4_095)
        let json = try query { () throws(QueryValueError) in try QueryJSONValue(bytes: ByteString(utf8: text), limits: limits) }
        let retainedChild = try query { () throws(QueryValueError) in
            let value = try QueryJSONBValue(json: json, limits: limits)
            let encoded = try QueryFieldStorageAdapter.encode(.jsonb(value), type: .sql(.jsonb), limits: limits)
            let decoded = try QueryFieldStorageAdapter.decode(encoded, type: .sql(.jsonb), limits: limits)
            guard case .jsonb(let restored) = decoded, restored == value,
                  restored.hashValue == value.hashValue,
                  case .array(let children) = restored.root else { throw .nonCanonicalJSONB }
            return children[0]
        }
        let footprint = retainedChild.storageFootprint
        try require(footprint.nodeCapacity >= 4_096 && footprint.retainedStorageByteCount > 0, code: 16)
        var current = retainedChild
        for _ in 0..<4_094 {
            guard case .array(let children) = current, children.count == 1 else { throw .assertion(17) }
            current = children[0]
        }
        guard case .number(let number) = current else { throw .assertion(18) }
        try require(number.displayScale == 6, code: 19)
        // The final child view and its complete flat owner are released on return.
    }

    private static func invalidValues(deepRoot: QueryJSONBNode) throws(Failure) {
        var rejected = false
        do {
            _ = try QueryJSONValue(bytes: ByteString(utf8: "[1,]"), limits: limits)
        } catch {
            guard case .invalidJSON = error else { throw .query(error) }
            rejected = true
        }
        try require(rejected, code: 20)
        rejected = false
        do {
            _ = try QueryNumericValue(value: ExactDecimal(coefficient: 123, scale: 2), displayScale: 1)
        } catch {
            guard case .invalidNumericDisplayScale = error else { throw .query(error) }
            rejected = true
        }
        try require(rejected, code: 22)
        let shallow = QueryValueLimits(maximumRetainedBytes: 4_000_000, maximumTotalNodes: 20_000,
                                        maximumNestingDepth: 1, maximumCollectionElements: 20_000)
        rejected = false
        do {
            _ = try QueryJSONBNode.array([deepRoot], limits: shallow)
        } catch {
            guard case .resourceLimit(let resource, _, _) = error, resource == "depth" else { throw .query(error) }
            rejected = true
        }
        try require(rejected, code: 24)
    }

    private static func wireFailures(columns: [QueryColumn], row: QueryRow) throws(Failure) {
        try require(DatabaseWireLimits.maximumSupportedNestingDepth == 1_024, code: 30)
        let page = try makePage(columns: columns, rows: [row])
        let frame = try wire { () throws(DatabaseWireError) in
            try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 19, response: .rows(page))
        }
        var rejected = false
        do {
            _ = try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame[0..<1], matching: 19)
        } catch {
            guard error == .truncated else { throw .wire(error) }
            rejected = true
        }
        try require(rejected, code: 26)
        let bounded: DatabaseWireLimits
        do {
            bounded = try DatabaseWireLimits(maximumFrameBytes: 1, maximumStringBytes: 1,
                maximumByteStringBytes: 1, maximumCollectionCount: 1,
                maximumNestingDepth: 1, maximumObjectCount: 1)
        } catch { throw .wireLimits(error) }
        rejected = false
        do {
            _ = try DatabaseWireDecoder(limits: bounded).decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 19)
        } catch {
            guard case .frameTooLarge = error else { throw .wire(error) }
            rejected = true
        }
        try require(rejected, code: 28)
    }

    private static func sqlConstructorsAndTemporalDescriptors() throws(Failure) {
        for zone in [false, true] {
            for precision: Int? in [nil, 0, 3, 6] {
                for isTime in [false, true] {
                    let type: DataType = isTime ? .time(withTimeZone: zone, precision: precision)
                        : .timestamp(withTimeZone: zone, precision: precision)
                    let parameter = QueryParameter(position: 1, name: "instant", value: .primitive(.null), type: .sql(type))
                    let expression: Expression = .row([
                        .array([.parameter(.position(1)), .null]),
                        .cast(.parameter(.name("instant")), targetType: type), .row([]), .array([]),
                    ])
                    let statement = select(expression)
                    do { try QueryStructuralValidator.validate(statement) }
                    catch { throw .structure(error) }
                    let expectedValue: Expression = .literal(.queryValue(.primitive(.null), type: .sql(type)))
                    let expected = select(.row([
                        .array([expectedValue, .null]), .cast(expectedValue, targetType: type), .row([]), .array([]),
                    ]))
                    let bound: QueryStatement
                    do { bound = try QueryParameterBinder(parameters: [parameter]).bind(statement) }
                    catch { throw .binding(error) }
                    try require(bound == expected, code: 34)
                    for original in [statement, bound] {
                        let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(original) }
                        let decoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) }
                        try require(decoded == original && decoded.hashValue == original.hashValue, code: 35)
                    }
                    let request = QueryExecuteOperation.Request(input: .ir(statement), parameters: [parameter])
                    let frame = try wire { () throws(DatabaseWireError) in
                        #if DATABASE_KIT_MULTI_BASE
                        try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 20,
                            target: .database, request: request)
                        #else
                        try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 20, request: request)
                        #endif
                    }
                    let decoded = try wire { () throws(DatabaseWireError) in
                        try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame)
                    }
                    try require(decoded.request == request, code: 36)
                    if precision != nil {
                        let inferred: DataType = isTime ? .time(withTimeZone: zone) : .timestamp(withTimeZone: zone)
                        try require(type != inferred, code: 37)
                    }
                }
            }
        }
        let missing = select(.array([.row([.parameter(.position(2))])]))
        var rejected = false
        do { _ = try QueryParameterBinder(parameters: []).bind(missing) }
        catch {
            guard error == .missingPosition(2) else { throw .binding(error) }
            rejected = true
        }
        try require(rejected, code: 38)
        let nested: Expression = .array([.row([.string("abcd")])])
        do { try QueryStructuralValidator.validate(nested) }
        catch { throw .structure(error) }
        for (bounded, expected): (QueryStructuralLimits, QueryStructuralValidationError) in [
            (QueryStructuralLimits(maximumNestingDepth: 2), .resourceLimitExceeded(resource: .nestingDepth, actual: 3, maximum: 2)),
            (QueryStructuralLimits(maximumCollectionElements: 1), .resourceLimitExceeded(resource: .collectionElements, actual: 2, maximum: 1)),
        ] {
            rejected = false
            do { try QueryStructuralValidator.validate(nested, limits: bounded) }
            catch {
                guard error == expected else { throw .structure(error) }
                rejected = true
            }
            try require(rejected, code: 39)
        }
        rejected = false
        let retained: Expression = .array([.literal(.queryValue(.primitive(.string("abcd")), type: .sql(.text)))])
        do { try QueryStructuralValidator.validate(retained, limits: QueryStructuralLimits(maximumRetainedBytes: 3)) }
        catch {
            guard error == .resourceLimitExceeded(resource: .retainedBytes, actual: 4, maximum: 3) else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 50)
        for precision in [-1, 7, Int.max] {
            for type: DataType in [.time(withTimeZone: false, precision: precision), .timestamp(withTimeZone: true, precision: precision)] {
                try require(!QueryValueValidator.accepts(.primitive(.null), type: .sql(type)), code: 40)
                rejected = false
                do { try QueryStructuralValidator.validate(.cast(.null, targetType: type)) }
                catch {
                    guard error == .invalidQueryValue(.incompatibleType) else { throw .structure(error) }
                    rejected = true
                }
                try require(rejected, code: 41)
                try rejectWire(.invalidQueryValue(.incompatibleType), code: 42) { () throws(DatabaseWireError) in
                    _ = try QueryIRWireFormat.encode(select(.cast(.null, targetType: type)))
                }
            }
        }
        let oneChild: DatabaseWireLimits
        do {
            oneChild = try DatabaseWireLimits(maximumFrameBytes: 4_096, maximumStringBytes: 4_096,
                maximumByteStringBytes: 4_096, maximumCollectionCount: 1, maximumNestingDepth: 64, maximumObjectCount: 1_000)
        } catch { throw .wireLimits(error) }
        for constructor: Expression in [.array([.null]), .row([.null])] {
            let encoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(select(constructor)) }
            let tag: UInt8 = if case .array = constructor { 41 } else { 42 }
            // Mutate the unique constructor tag in a canonical public statement, preserving its envelope.
            var bytes = Array(encoded)
            guard let offset = bytes.firstIndex(of: tag), bytes[offset + 1] == 1 else { throw .assertion(43) }
            try rejectWire(.truncated, code: 44) { () throws(DatabaseWireError) in
                _ = try QueryIRWireFormat.decode(encoded[0..<(offset + 5)])
            }
            bytes[offset + 1] = 2
            try rejectWire(.collectionTooLarge(actual: 2, maximum: 1), code: 49) { () throws(DatabaseWireError) in
                _ = try QueryIRWireFormat.decode(ByteString(bytes), limits: oneChild)
            }
            bytes[offset + 1] = 1
            bytes[offset] = 255
            try rejectWire(.invalidValueTag(255), code: 45) { () throws(DatabaseWireError) in
                _ = try QueryIRWireFormat.decode(ByteString(bytes))
            }
        }
        for type: DataType in [.time(withTimeZone: false, precision: 3), .timestamp(withTimeZone: true, precision: 3)] {
            let encoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(select(.cast(.null, targetType: type))) }
            let tag: UInt8 = if case .time = type { 22 } else { 23 }
            var bytes = Array(encoded)
            guard let offset = bytes.firstIndex(of: tag), bytes[offset + 2] == 3 else { throw .assertion(46) }
            try rejectWire(.truncated, code: 47) { () throws(DatabaseWireError) in
                _ = try QueryIRWireFormat.decode(encoded[0..<(offset + 2)])
            }
            bytes[offset + 2] = 7
            try rejectWire(.invalidQueryValue(.incompatibleType), code: 48) { () throws(DatabaseWireError) in
                _ = try QueryIRWireFormat.decode(ByteString(bytes))
            }
        }
    }

    private static func select(_ expression: Expression) -> QueryStatement {
        .select(SelectQuery(projection: .items([ProjectionItem(expression)]), source: .values([], columnNames: nil)))
    }

    private static func rejectWire(_ expected: DatabaseWireError, code: UInt8,
                                   _ body: () throws(DatabaseWireError) -> Void) throws(Failure) {
        var rejected = false
        do { try body() }
        catch {
            guard error == expected else { throw .wire(error) }
            rejected = true
        }
        try require(rejected, code: code)
    }

    private static func query<Value>(_ body: () throws(QueryValueError) -> Value) throws(Failure) -> Value {
        do { return try body() } catch { throw .query(error) }
    }

    private static func wire<Value>(_ body: () throws(DatabaseWireError) -> Value) throws(Failure) -> Value {
        do { return try body() } catch { throw .wire(error) }
    }

    private static func require(_ condition: Bool, code: UInt8) throws(Failure) {
        guard condition else { throw .assertion(code) }
    }

    private static func pass(_ name: String) { print("QUERY_VALUE_RUNTIME_CASE \(name) PASS") }
}
