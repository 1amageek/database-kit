import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) import DatabaseWire
#if canImport(WASILibc)
import WASILibc
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A bounded executable fixture, without a testing runtime dependency.
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
        case catalog(SQLCatalogError)
        case interpolation(SQLInterpolationError)
    }

    private static let limits = QueryValueLimits(
        maximumRetainedBytes: 4_000_000, maximumTotalNodes: 20_000,
        maximumNestingDepth: 5_000, maximumCollectionElements: 20_000
    )

    static func main() async {
        print("QUERY_VALUE_RUNTIME_BEGIN")
        do {
            try run()
            try await unifiedExecution()
            pass("unified-query-execution")
            print("QUERY_VALUE_RUNTIME_PASS cases=18")
        } catch {
            switch error {
            case .assertion(let code): print("QUERY_VALUE_RUNTIME_FAIL assertion=\(code)")
            case .query: print("QUERY_VALUE_RUNTIME_FAIL query")
            case .wire: print("QUERY_VALUE_RUNTIME_FAIL wire")
            case .time: print("QUERY_VALUE_RUNTIME_FAIL time")
            case .wireLimits: print("QUERY_VALUE_RUNTIME_FAIL wire-limits")
            case .structure: print("QUERY_VALUE_RUNTIME_FAIL structure")
            case .binding: print("QUERY_VALUE_RUNTIME_FAIL binding")
            case .catalog: print("QUERY_VALUE_RUNTIME_FAIL catalog")
            case .interpolation: print("QUERY_VALUE_RUNTIME_FAIL interpolation")
            }
            exit(1)
        }
    }

    private static func unifiedExecution() async throws(Failure) {
        let bound: SQL
        do { bound = try "SELECT \(Int32(42)), \("x'); DROP TABLE items; --")" }
        catch { throw .interpolation(error) }
        try require(bound.text == "SELECT $1, $2" && bound.parameters.count == 2, code: 149)
        let statement = select(.literal(.int(42)))
        let block: SQLBlock
        do { block = try SQLBlock(steps: [.statement(statement)]) }
        catch { throw .structure(error) }
        for input in [QueryInput.sql("SELECT 42"), .statement(statement), .block(block)] {
            let request = QueryExecuteOperation.Request(input: input)
            let decoded = try wire { () throws(DatabaseWireError) in
                let bytes = try DatabaseWireEncoder().encodeRequestPayload(DatabaseOperationCatalog.queryExecute, request: request)
                return try DatabaseWireDecoder().decodeRequestPayload(DatabaseOperationCatalog.queryExecute, from: bytes)
            }
            try require(decoded.input == input && decoded.page == nil, code: 150)
        }
        let column = try query { () throws(QueryValueError) in
            try QueryColumn(number: 1, name: "value", type: .sql(.integer), isNullable: false)
        }
        let expected = QueryRow(values: [.primitive(.int32(42))])
        let rows = try wire { () throws(DatabaseWireError) in
            let response = QueryExecuteOperation.Response.rows(try QueryRowPage(columns: [column], rows: [expected], affectedRows: 1))
            let frame = try DatabaseWireEncoder().encodeResponse(DatabaseOperationCatalog.queryExecute, requestID: 19, response: response)
            return try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute, from: frame, matching: 19)
        }
        guard case .success(.rows(let page)) = rows else { throw .assertion(151) }
        let result = QueryResult<QueryRowPage, RDFGraphPage, Bool>.rows(page)
        var iterator = result.rows.makeAsyncIterator()
        let first: QueryRow?
        let second: QueryRow?
        do {
            first = try await iterator.next()
            second = try await iterator.next()
        } catch { throw .wire(error) }
        try require(first == expected, code: 152)
        try require(second == nil, code: 153)
        try require(page.columns == [column] && page.affectedRows == 1, code: 155)
        // Exercise the same scoped projection used before execution commits.
        do {
            let quad = RDFQuad(subject: .iri(try RDFIRI("urn:s")),
                predicate: RDFPredicateIRI(try RDFIRI("urn:p")), object: .iri(try RDFIRI("urn:o")))
            func project(_ writer: inout QueryResponseWriter) throws {
                #if DATABASE_KIT_MULTI_BASE
                let consistency = DatabaseReadConsistency.transactional(
                    try DomainReadPoint(domainID: "fixture", position: .version(1)))
                try writer.writeRDFGraph(quadCount: 1, consistency: consistency) { quads in try quads.write(quad) }
                try writer.writeBoolean(QueryBooleanResult(value: true, provenance: nil, consistency: consistency))
                #else
                try writer.writeRDFGraph(quadCount: 1) { quads in try quads.write(quad) }
                try writer.writeBoolean(true)
                #endif
                try writer.writeRows(columnCount: 1, rowCount: 1, affectedRows: 1) { rows in
                    try rows.writeColumn(column)
                    try rows.beginRow()
                    try rows.writeValue(.primitive(.int32(42)))
                    try rows.endRow()
                }
            }
            let encoder = DatabaseWireEncoder()
            let count = try encoder.measureQueryResponse(requestID: 20, resultCount: 3, body: project)
            var bytes = [UInt8](repeating: 0, count: count)
            try bytes.withUnsafeMutableBytes { destination in
                try encoder.encodeQueryResponse(requestID: 20, resultCount: 3, into: destination, body: project)
            }
            let projected = try DatabaseWireDecoder().decodeResponse(DatabaseOperationCatalog.queryExecute,
                from: ByteString(bytes), matching: 20)
            guard case .success(.block(let outcomes)) = projected, outcomes.count == 3,
                  case .rdfGraph(let graph) = outcomes[0],
                  case .boolean(let truth) = outcomes[1], truth.value, case .rows(let rows) = outcomes[2] else {
                throw Failure.assertion(156)
            }
            try require(try graph.materializedQuads(maximumCount: 1) == [quad], code: 159)
            try require(rows.columns == [column] && rows.affectedRows == 1, code: 157)
        } catch let error as Failure { throw error }
        catch let error as DatabaseWireError { throw .wire(error) }
        catch { throw .assertion(158) }
    }

    private static func run() throws(Failure) {
        let time: TimeSpan
        do { time = try TimeSpan(seconds: -1, nanoseconds: 999_999_000) }
        catch { throw .time(error) }
        let values = try query { () throws(QueryValueError) in try richValues(time: time) }
        let types: [QueryColumnType] = [
            .sql(.decimal(precision: nil, scale: nil)), .sql(.json), .sql(.jsonb),
            .sql(.array(.integer)), .sql(.interval()),
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
        try sqlConditionalCarriage()
        pass("sql-conditional-carriage")
        try sqlLexicalValueConstruction()
        pass("sql-lexical-value-construction")
        try sqlPatternConcatenationCarriage()
        pass("sql-pattern-concatenation-carriage")
        try sqlTemporalValueCarriage()
        pass("sql-temporal-value-carriage")
        try sqlCompositeValueCarriage()
        pass("sql-composite-value-carriage")
        try sqlRelationalQueryCarriage()
        pass("sql-relational-query-carriage")
        try sqlGroupingAggregateWindowCarriage()
        pass("sql-grouping-aggregate-window-carriage")
        try sqlRecursiveFunctionCarriage()
        pass("sql-recursive-function-carriage")
        try sqlCatalogDeclarations()
        pass("sql-catalog-declarations")
    }

    private static func sqlCatalogDeclarations() throws(Failure) {
        let composed = "\u{00e9}"
        let decomposed = "e\u{0301}"
        let first = try catalog { () throws(SQLCatalogError) in
            try SQLColumn(id: composed, name: composed, fieldNumber: 9)
        }
        let second = try catalog { () throws(SQLCatalogError) in
            try SQLColumn(id: decomposed, name: decomposed, fieldNumber: 2)
        }
        let namespace = try catalog { () throws(SQLCatalogError) in
            try SQLNamespace(id: "namespace", name: "public")
        }
        let relation = try catalog { () throws(SQLCatalogError) in
            try SQLRelation(id: "relation", namespaceID: "namespace", name: "items", entityName: "Item",
                columns: [first, second], primaryKeyColumnIDs: [decomposed, composed])
        }
        let declaration = try catalog { () throws(SQLCatalogError) in
            try SQLCatalog(namespaces: [namespace], relations: [relation])
        }
        try require(declaration.relations.count == 1 && relation.columns[0].fieldNumber == 9
            && relation.primaryKeyColumnIDs?[0].utf8.elementsEqual(decomposed.utf8) == true, code: 242)
        try require(first != second && Set([first, second]).count == 2, code: 243)
        let noKey = try catalog { () throws(SQLCatalogError) in
            try SQLRelation(id: "relation", namespaceID: "namespace", name: "items", entityName: "Item", columns: [])
        }
        try require(noKey.primaryKeyColumnIDs == nil && noKey.columns.isEmpty, code: 244)
        try rejectCatalog(.emptyIdentifier, code: 245) { () throws(SQLCatalogError) in
            _ = try SQLNamespace(id: "namespace", name: "")
        }
        try rejectCatalog(.nulInIdentifier, code: 246) { () throws(SQLCatalogError) in
            _ = try SQLSearchPath(entries: [.schema("bad\u{0}name")])
        }
        try rejectCatalog(.invalidFieldNumber(0), code: 247) { () throws(SQLCatalogError) in
            _ = try SQLColumn(id: "column", name: "value", fieldNumber: 0)
        }
        try rejectCatalog(.unknownNamespaceID("namespace"), code: 248) { () throws(SQLCatalogError) in
            _ = try SQLCatalog(namespaces: [], relations: [relation])
        }
        try rejectCatalog(.duplicatePrimaryKeyColumnID(composed), code: 249) { () throws(SQLCatalogError) in
            _ = try SQLRelation(id: "r", namespaceID: "n", name: "items", entityName: "Item",
                columns: [first], primaryKeyColumnIDs: [composed, composed])
        }
        try rejectCatalog(.unknownPrimaryKeyColumnID(decomposed), code: 250) { () throws(SQLCatalogError) in
            _ = try SQLRelation(id: "r", namespaceID: "n", name: "items", entityName: "Item",
                columns: [first], primaryKeyColumnIDs: [decomposed])
        }
        try rejectCatalog(.emptyPrimaryKey, code: 251) { () throws(SQLCatalogError) in
            _ = try SQLRelation(id: "r", namespaceID: "n", name: "items", entityName: "Item",
                columns: [], primaryKeyColumnIDs: [])
        }
        try require(SQLSearchPath.default.entries == [.currentUser, .schema("public")], code: 252)
        let entries: [SQLSearchPathEntry] = [.schema(composed), .schema(decomposed), .schema(composed)]
        let path = try catalog { () throws(SQLCatalogError) in try SQLSearchPath(entries: entries) }
        try require(path.entries == entries && Set(path.entries).count == 2, code: 253)
        let renamed = try catalog { () throws(SQLCatalogError) in
            try SQLRelation(id: relation.id, namespaceID: relation.namespaceID, name: "renamed", entityName: relation.entityName,
                columns: relation.columns, primaryKeyColumnIDs: relation.primaryKeyColumnIDs)
        }
        try require(renamed.id == relation.id && renamed.columns == relation.columns
            && Set([renamed, relation]).count == 2, code: 254)
        try rejectCatalog(.duplicateEntityName("Item"), code: 255) { () throws(SQLCatalogError) in
            let alias = try SQLRelation(id: "alias", namespaceID: "namespace", name: "alias", entityName: "Item", columns: [])
            _ = try SQLCatalog(namespaces: [namespace], relations: [relation, alias])
        }
    }

    private static func sqlRecursiveFunctionCarriage() throws(Failure) {
        let constant = Literal.binary(ByteString([1, 2, 3, 4]))
        let definition = NamedSubquery(name: "c", columns: ["k"],
            query: SelectQuery(projection: [.expression(.int(1))], source: .values([[]])),
            search: CTESearchClause(order: .breadthFirst, columns: ["k"], sequenceColumn: "sequence"),
            cycle: CTECycleClause(columns: ["k"], markColumn: "mark", pathColumn: "path",
                markValue: constant, defaultValue: .null))
        let call = FunctionCall(name: "generate_series", arguments: [.int(1), .parameter(.position(1))], schema: "pg_catalog")
        let query = SelectQuery(projection: [.wildcard()], source: .aliased(
            .tableFunction(TableFunctionSource(function: call, withOrdinality: true)), name: "f", columns: ["value", "ordinal"]),
            subqueries: [definition], withRecursive: true)
        let original = QueryStatement.select(query)
        do { try QueryStructuralValidator.validate(original) } catch { throw .structure(error) }
        let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(original) }
        let restored = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) }
        try require(restored == original && restored.hashValue == original.hashValue, code: 231)
        let bound: QueryStatement
        do {
            let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(3)))])
            bound = try binder.bind(restored)
        } catch { throw .binding(error) }
        guard case .select(let selected) = bound,
              case .aliased(.tableFunction(let function), _, _) = selected.source else { throw .assertion(232) }
        try require(selected.withRecursive && function.withOrdinality && function.function.arguments == [.int(1), .int(3)], code: 233)
        try require(selected.subqueries?[0].search == definition.search && selected.subqueries?[0].cycle == definition.cycle, code: 234)
        try require(query != query.replacing(withRecursive: false), code: 235)
        try sqlRecursiveFunctionWireFailures(original, bytes: bytes)
    }

    @inline(never)
    private static func sqlRecursiveFunctionWireFailures(_ statement: QueryStatement, bytes: ByteString) throws(Failure) {
        for count in 0..<bytes.count {
            var rejected = false
            do { _ = try QueryIRWireFormat.decode(bytes.prefix(count)) } catch { rejected = true }
            try require(rejected, code: 236)
        }
        var malformed = Array(bytes)
        malformed[malformed.count - 1] = 2
        try rejectWire(.invalidBool(2), code: 237) { () throws(DatabaseWireError) in
            _ = try QueryIRWireFormat.decode(ByteString(malformed))
        }
        let exact: DatabaseWireLimits
        let onePast: DatabaseWireLimits
        do {
            exact = try DatabaseWireLimits(maximumFrameBytes: bytes.count, maximumStringBytes: 64,
                maximumByteStringBytes: 64, maximumCollectionCount: 2, maximumNestingDepth: 64, maximumObjectCount: 256)
            onePast = try DatabaseWireLimits(maximumFrameBytes: bytes.count - 1, maximumStringBytes: 64,
                maximumByteStringBytes: 64, maximumCollectionCount: 2, maximumNestingDepth: 64, maximumObjectCount: 256)
        } catch { throw .wireLimits(error) }
        try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(statement, limits: exact) } == bytes, code: 238)
        try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes, limits: exact) } == statement, code: 239)
        var rejected = false
        do { _ = try QueryIRWireFormat.decode(bytes, limits: onePast) } catch {
            guard case .frameTooLarge = error else { throw .wire(error) }
            rejected = true
        }
        try require(rejected, code: 240)
        let invalid = NamedSubquery(name: "c", query: SelectQuery(projection: [], source: .values([])),
            cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .bool(true)))
        try rejectWire(.invalidQueryStructure(.invalidCTECycleClause), code: 241) { () throws(DatabaseWireError) in
            _ = try QueryIRWireFormat.encode(.select(SelectQuery(projection: [], source: .values([]), subqueries: [invalid])))
        }
    }

    private static func sqlGroupingAggregateWindowCarriage() throws(Failure) {
        let parameter = Expression.parameter(.position(1))
        let aggregate = SQLAggregateCall(function: .arrayAgg, arguments: [parameter], distinct: true,
            orderBy: [SortKey(parameter)], filter: parameter, withinGroup: [], schema: "pg_catalog")
        let spec = WindowSpecification(inheritedName: "base", partitionBy: [parameter], orderBy: [SortKey(parameter)],
            frame: WindowFrame(mode: .groups, start: .preceding(parameter), end: .following(parameter), exclusion: .ties))
        let query = SelectQuery(projection: [ProjectionItem(.aggregate(.sql(aggregate))), ProjectionItem(.grouping([parameter])),
            ProjectionItem(.window(WindowCall(function: .analytic(.lag, arguments: [parameter]), reference: .specification(spec))))],
            source: .values([[]]), groupBy: [.groupingSets([[], [.rollup([[parameter], [parameter, parameter]])], [.cube([[parameter]])]])],
            windows: [NamedWindow(name: "named", specification: spec)])
        let encoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(.select(query)) }
        let decoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(encoded) }
        try require(decoded == .select(query), code: 220)
        try require(query.hashValue == query.replacing(windows: query.windows).hashValue, code: 221)
        let bound: QueryStatement
        do {
            let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(7)))])
            bound = try binder.bind(decoded)
        } catch { throw .binding(error) }
        guard case .select(let result) = bound,
              case .expression(.aggregate(.sql(let restored)), _) = result.projection[0],
              case .expression(.window(let call), _) = result.projection[2],
              case .specification(let inline) = call.reference else { throw .assertion(222) }
        try require(restored.arguments == [.int(7)] && restored.filter == .int(7) && restored.withinGroup == [], code: 223)
        try require(inline.partitionBy == [.int(7)] && inline.frame?.start == .preceding(.int(7))
            && inline.frame?.end == .following(.int(7)) && result.windows[0].specification == inline, code: 224)
        var rejectedParameter = false
        do { try QueryParameterBinder(parameters: []).validate(decoded) } catch {
            guard error == .missingPosition(1) else { throw .binding(error) }
            rejectedParameter = true
        }
        try require(rejectedParameter, code: 225)
        let referenceSpec = WindowSpecification(partitionBy: [.col("c")], frame: WindowFrame(mode: .rows,
            start: .preceding(.col("d")), end: .following(.col("e"))))
        let column = Expression.window(WindowCall(function: .aggregate(SQLAggregateCall(function: .sum,
            arguments: [.col("a")], filter: .col("b"))), reference: .specification(referenceSpec)))
        try require(SelectQuery(projection: [ProjectionItem(column)], source: .values([[]])).referencedColumns == Set(["a", "b", "c", "d", "e"].map(ColumnRef.init)), code: 226)
        var rejectedDepth = false
        do { try QueryStructuralValidator.validate(query, limits: QueryStructuralLimits(maximumNestingDepth: 2)) } catch {
            guard case .resourceLimitExceeded(resource: .nestingDepth, actual: _, maximum: 2) = error else { throw .structure(error) }
            rejectedDepth = true
        }
        try require(rejectedDepth, code: 227)
        var rejectedSPARQL = false
        do { _ = try column.toSPARQL() } catch { rejectedSPARQL = true }
        try require(rejectedSPARQL, code: 228)
        for count in 0..<encoded.count {
            var rejectedPrefix = false
            do { _ = try QueryIRWireFormat.decode(encoded[0..<count]) } catch { rejectedPrefix = true }
            try require(rejectedPrefix, code: 229)
        }
        var nested = GroupingElement.expression(.int(1))
        var independent = GroupingElement.expression(.int(1))
        for _ in 0..<48 { nested = .groupingSets([[nested]]); independent = .groupingSets([[independent]]) }
        try require(nested == independent && nested.hashValue == independent.hashValue, code: 230)
    }

    private static func sqlCompositeValueCarriage() throws(Failure) {
        // Escaped child views must retain their complete immutable value owner.
        let fields = try query { () throws(QueryValueError) -> QueryValueElements in
            let scalar = try QueryColumn(number: 1, name: "value", type: .sql(.integer), isNullable: false)
            let type = try QueryCompositeType(columns: [scalar], limits: limits)
            let row = try QueryCompositeValue(type: type, fields: [.primitive(.int32(7))], limits: limits)
            let dimension = try QueryArrayDimension(lowerBound: -4, length: 2)
            let array = try QueryArrayValue(elementType: .composite(type), dimensions: [dimension],
                elements: [.composite(row), .primitive(.null)], limits: limits)
            let columns = [
                try QueryColumn(number: 1, name: "same", type: .sql(.array(.composite(type))), isNullable: false),
                try QueryColumn(number: 2, name: "same", type: .sql(.composite(type)), isNullable: true),
            ]
            let outer = try QueryCompositeType(columns: columns, limits: limits)
            return try QueryCompositeValue(type: outer, fields: [.array(array), .composite(row)], limits: limits).fields
        }
        guard case .array(let array) = fields[0], case .composite(let row) = fields[1] else {
            throw .assertion(210)
        }
        try require(array.dimensions[0].lowerBound == -4 && array.elements[1].isNull, code: 211)
        try require(row.fields[0] == .primitive(.int32(7)) && array.elements[0] == .composite(row), code: 212)
        let column = try query { () throws(QueryValueError) in
            try QueryColumn(number: 1, name: "row", type: .sql(.composite(row.type)), isNullable: true)
        }
        let expected = [QueryRow(values: [.primitive(.null)]), QueryRow(values: [.composite(row)])]
        let page = try retainedPage(columns: [column], rows: expected)
        try require(page.columns == [column], code: 213)
        try require(try wire { () throws(DatabaseWireError) in try page.materializedRows(maximumCount: 2) } == expected, code: 214)
        let empty = try retainedPage(columns: [column], rows: [])
        try require(empty.rowCount == 0 && empty.columns == [column], code: 215)
        let null = QueryParameter(position: 1, value: .primitive(.null), type: column.type)
        let request = QueryExecuteOperation.Request(input: .text(language: .sql, statement: "SELECT $1"), parameters: [null])
        let frame = try wire { () throws(DatabaseWireError) in
            #if DATABASE_KIT_MULTI_BASE
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 21,
                target: .database, request: request)
            #else
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 21, request: request)
            #endif
        }
        let decoded = try wire { () throws(DatabaseWireError) in
            try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame)
        }
        try require(decoded.request.parameters == [null], code: 216)
        let footprint = try query { () throws(QueryValueError) in try QueryValueValidator.measure(.composite(row)) }
        let exact = QueryValueLimits(maximumRetainedBytes: footprint.retainedByteCount,
            maximumTotalNodes: footprint.nodeCount, maximumNestingDepth: footprint.maximumNestingDepth,
            maximumCollectionElements: footprint.collectionElementCount)
        try query { () throws(QueryValueError) in try QueryValueValidator.validate(.composite(row), limits: exact) }
        let short = QueryValueLimits(maximumRetainedBytes: footprint.retainedByteCount,
            maximumTotalNodes: footprint.nodeCount - 1, maximumNestingDepth: footprint.maximumNestingDepth,
            maximumCollectionElements: footprint.collectionElementCount)
        try rejectQuery(.resourceLimit(resource: "nodes", actual: footprint.nodeCount, maximum: footprint.nodeCount - 1), code: 217) {
            () throws(QueryValueError) in try QueryValueValidator.validate(.composite(row), limits: short)
        }
        for type: QueryColumnType in [.sql(.composite(row.type)), .sql(.array(.composite(row.type)))] {
            try rejectQuery(.invalidPersistenceDescriptor, code: 218) { () throws(QueryValueError) in
                try QueryFieldStorageAdapter.validateDescriptor(type, fieldType: .object, isArray: false)
            }
        }
        let deep = try query { () throws(QueryValueError) -> QueryValue in
            var builder = QueryValueBuilder(limits: limits)
            var child = try builder.append(.primitive(.int32(7)))
            var type: DataType = .integer
            for _ in 0..<32 {
                let column = try QueryColumn(number: 1, name: "nested", type: .sql(type), isNullable: false)
                let composite = try QueryCompositeType(columns: [column], limits: limits)
                child = try builder.appendComposite(type: composite, fields: [child])
                type = .composite(composite)
            }
            return try builder.finish(root: child)
        }
        let copy = try query { () throws(QueryValueError) in
            var builder = QueryValueBuilder(limits: limits)
            let root = try builder.append(deep)
            return try builder.finish(root: root)
        }
        try require(deep == copy && deep.hashValue == copy.hashValue, code: 219)
    }

    private static func sqlRelationalQueryCarriage() throws(Failure) {
        let parameter = Expression.parameter(.position(1))
        let inner = SelectQuery(projection: [ProjectionItem(parameter, alias: "value")], source: .values([[]]))
        let query = SelectQuery(
            projection: [.wildcard(qualifier: "input"), ProjectionItem(.fieldExpansion(.wholeRow("input"))),
                ProjectionItem(.field(.wholeRow("input"), name: "value")),
                ProjectionItem(.collate(parameter, collation: .posix)), ProjectionItem(.arraySubquery(inner))],
            source: .aliased(.values([[parameter]]), name: "input", columns: ["value"]),
            orderBy: [SortKey(.collate(.col("value"), collation: .c), nulls: .last)],
            quantifier: .distinctOn([parameter]),
            pagination: QueryPagination(limit: .count(.expression(parameter), withTies: true), offset: .expression(parameter)),
            subqueries: [NamedSubquery(name: "declared", columns: ["value"], query: inner, materialized: .materialized)])
        let set = SelectQuery(projection: [.wildcard()], source: .setOperation(
            operator: .except, quantifier: .all, left: query, right: query),
            orderBy: [SortKey(.int(1))], pagination: QueryPagination(limit: .all))
        let joined = SelectQuery(projection: [.wildcard(qualifier: "joined")], source: .aliased(.join(
            JoinClause(type: .cross, left: .values([[parameter]]), right: .subquery(inner))),
            name: "joined", columns: ["left", "right"]))
        let derived = SelectQuery(projection: [.wildcard()], source: .subquery(inner))
        let unsigned = SelectQuery(projection: [.wildcard()], source: .graphPattern(.basic([])),
            quantifier: .distinct, pagination: QueryPagination(limit: .count(.fixed(.max), withTies: false), offset: .fixed(.max)))
        for value in [query, set, joined, derived, unsigned] {
            let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(.select(value)) }
            try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) } == .select(value), code: 130)
        }
        let expansion = Expression.fieldExpansion(.row([.int(1), .int(2)]))
        for rows: [[Expression]] in [
            [[expansion], [.int(3), .int(4)]],
            [[.int(3)], [.int(4), .int(5)], [expansion]],
            // Equal raw widths defer the final expanded mismatch to runtime binding.
            [[expansion], [.int(3)]],
        ] {
            let value = SelectQuery(projection: [.wildcard()], source: .values(rows))
            do { try QueryStructuralValidator.validate(value) } catch { throw .structure(error) }
            let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(.select(value)) }
            try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) } == .select(value), code: 140)
        }
        let nestedExpansion = SelectQuery(projection: [.wildcard()],
            source: .values([[.row([expansion])], [.int(3), .int(4)]]))
        var rejectedNestedExpansion = false
        do { try QueryStructuralValidator.validate(nestedExpansion) }
        catch {
            guard error == .invalidValuesRowArity(row: 1, expected: 1, actual: 2) else { throw .structure(error) }
            rejectedNestedExpansion = true
        }
        try require(rejectedNestedExpansion, code: 141)
        let text: String
        do { text = try unsigned.toSPARQL() } catch { throw .assertion(131) }
        try require(text == "SELECT DISTINCT *\nWHERE {\n\n}\nLIMIT 18446744073709551615\nOFFSET 18446744073709551615\n", code: 132)
        let binder: QueryParameterBinder
        let bound: QueryStatement
        do {
            binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.int64(9)))])
            bound = try binder.bind(.select(query))
        } catch { throw .binding(error) }
        guard case .select(let selected) = bound,
              case .aliased(.values(let rows), let name, let columns) = selected.source,
              case .expression(.arraySubquery(let nested), _) = selected.projection[4] else { throw .assertion(133) }
        try require(rows == [[.int(9)]] && name == "input" && columns == ["value"], code: 134)
        try require(nested.projection == [ProjectionItem(.int(9), alias: "value")]
            && selected.quantifier == .distinctOn([.int(9)])
            && selected.pagination == QueryPagination(limit: .count(.expression(.int(9)), withTies: true), offset: .expression(.int(9))), code: 135)
        var deep = parameter
        var expected = Expression.int(9)
        for _ in 0..<12 {
            deep = .subquery(SelectQuery(projection: [ProjectionItem(deep)], source: .values([[]])))
            expected = .subquery(SelectQuery(projection: [ProjectionItem(expected)], source: .values([[]])))
        }
        let deepStatement = select(.arraySubquery(SelectQuery(projection: [ProjectionItem(deep)], source: .values([[]]))))
        let expectedStatement = select(.arraySubquery(SelectQuery(projection: [ProjectionItem(expected)], source: .values([[]]))))
        let encoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(deepStatement) }
        let decoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(encoded) }
        let substituted: QueryStatement
        do { substituted = try binder.bind(decoded) } catch { throw .binding(error) }
        try require(substituted == expectedStatement, code: 136)
        try require(Set([expected, expected]).count == 1, code: 137)
        var arena = QueryOccurrenceArena()
        let first: QueryOccurrenceID
        let second: QueryOccurrenceID
        let firstRow: QueryOccurrenceID
        do {
            let root = try arena.append()
            firstRow = try arena.append(parent: root, field: .valuesRow, index: 0)
            let secondRow = try arena.append(parent: root, field: .valuesRow, index: 1)
            first = try arena.append(parent: firstRow, field: .valuesCell, index: 0)
            second = try arena.append(parent: secondRow, field: .valuesCell, index: 0)
        } catch { throw .assertion(138) }
        try require(first != second && arena.child(of: firstRow, field: .valuesCell, index: 0) == first, code: 138)
        var rejected = false
        do { try QueryStructuralValidator.validate(set.replacing(filter: .bool(true))) }
        catch {
            guard error == .invalidSetQueryEnvelope else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 139)
    }

    private static func sqlLexicalValueConstruction() throws(Failure) {
        let numeric = try query { () throws(QueryValueError) in
            try QueryNumericValue(sqlLexicalForm: " 1.2300e2 ", maximumUTF8Count: 10)
        }
        try require(numeric.value == ExactDecimal(coefficient: 123, scale: 0) && numeric.displayScale == 2, code: 58)
        let zero = try query { () throws(QueryValueError) in
            try QueryNumericValue(sqlLexicalForm: "-0.000", maximumUTF8Count: 6)
        }
        try require(zero.value.coefficient == 0 && zero.displayScale == 3, code: 59)
        let deepScale = try query { () throws(QueryValueError) in
            try QueryNumericValue(sqlLexicalForm: "1e-16383", maximumUTF8Count: 8)
        }
        try require(deepScale.displayScale == 16383, code: 60)
        let uuid = try query { () throws(QueryValueError) in
            try QueryValue.uuid(sqlLexicalForm: "{a0eebc999c0b4ef8bb6d6bb9bd380a11}", maximumUTF8Count: 34)
        }
        let equivalentUUID = try query { () throws(QueryValueError) in
            try QueryValue.uuid(sqlLexicalForm: "A0EE-BC99-9C0B-4EF8-BB6D-6BB9-BD38-0A11", maximumUTF8Count: 39)
        }
        try require(uuid == equivalentUUID, code: 61)
        let binary = try query { () throws(QueryValueError) in
            try QueryValue.binary(sqlLexicalForm: #"\001\377\\A"#, maximumUTF8Count: 11)
        }
        try require(binary == .primitive(.bytes([1, 255, 92, 65])), code: 62)
        let hexadecimal = try query { () throws(QueryValueError) in
            try QueryValue.binary(sqlLexicalForm: "\\x 00\tFF\n80\r", maximumUTF8Count: 12)
        }
        try require(hexadecimal == .primitive(.bytes([0, 255, 128])), code: 63)
        let values: [QueryValue] = [.numeric(numeric), uuid, binary]
        let types: [QueryColumnType] = [.sql(.decimal(precision: nil, scale: nil)), .sql(.uuid), .sql(.blob)]
        var columns: [QueryColumn] = []
        for (index, type) in types.enumerated() {
            columns.append(try query { () throws(QueryValueError) in
                try QueryColumn(number: UInt32(index + 1), name: "lexical", type: type, isNullable: false)
            })
        }
        let page = try retainedPage(columns: columns, rows: [QueryRow(values: values)])
        var rows = page.makeRowIterator()
        try require(try wire { () throws(DatabaseWireError) in try rows.next() } == QueryRow(values: values), code: 64)
        try rejectQuery(.resourceLimit(resource: "numeric input bytes", actual: 6, maximum: 5), code: 65) {
            () throws(QueryValueError) in _ = try QueryNumericValue(sqlLexicalForm: " 1.20 ", maximumUTF8Count: 5)
        }
        try rejectQuery(.resourceLimit(resource: "UUID input bytes", actual: 32, maximum: 31), code: 66) {
            () throws(QueryValueError) in _ = try QueryValue.uuid(sqlLexicalForm: "a0eebc999c0b4ef8bb6d6bb9bd380a11", maximumUTF8Count: 31)
        }
        try rejectQuery(.resourceLimit(resource: "binary input bytes", actual: 2, maximum: 1), code: 67) {
            () throws(QueryValueError) in _ = try QueryValue.binary(sqlLexicalForm: "é", maximumUTF8Count: 1)
        }
        try rejectQuery(.numericOutOfRange, code: 68) {
            () throws(QueryValueError) in _ = try QueryNumericValue(sqlLexicalForm: "1e-16384", maximumUTF8Count: 8)
        }
        try rejectQuery(.invalidNumeric(offset: 3, reason: "Repeated numeric decimal point"), code: 69) {
            () throws(QueryValueError) in _ = try QueryNumericValue(sqlLexicalForm: "1.2.3", maximumUTF8Count: 5)
        }
        try rejectQuery(.invalidUUID(offset: 0, reason: "Invalid UUID hexadecimal digit"), code: 70) {
            () throws(QueryValueError) in _ = try QueryValue.uuid(sqlLexicalForm: "x", maximumUTF8Count: 1)
        }
        try rejectQuery(.invalidBinary(offset: 3, reason: "Incomplete BYTEA hexadecimal byte"), code: 71) {
            () throws(QueryValueError) in _ = try QueryValue.binary(sqlLexicalForm: #"\x0"#, maximumUTF8Count: 3)
        }
        for text in ["\\x00\u{b}ff", "\\x00\u{c}ff"] {
            try rejectQuery(.invalidBinary(offset: 4, reason: "Invalid BYTEA hexadecimal digit"), code: 71) {
                () throws(QueryValueError) in _ = try QueryValue.binary(sqlLexicalForm: text[...], maximumUTF8Count: 7)
            }
        }
        try require(QueryValueValidator.accepts(.primitive(.null), type: .sql(.char(length: 10_485_760)))
            && !QueryValueValidator.accepts(.primitive(.null), type: .sql(.varchar(length: 10_485_761))), code: 72)
    }

    private static func sqlPatternConcatenationCarriage() throws(Failure) {
        let subject = Expression.parameter(.position(1))
        let pattern = Expression.parameter(.position(2))
        let escape = Expression.parameter(.position(3))
        let textType = QueryColumnType.sql(.text)
        let parameters = [QueryParameter(position: 1, value: .primitive(.string("é😀")), type: textType),
                          QueryParameter(position: 2, value: .primitive(.string("é_")), type: textType),
                          QueryParameter(position: 3, value: .primitive(.null), type: textType)]
        let boundSubject = Expression.literal(.queryValue(parameters[0].value, type: textType))
        let boundPattern = Expression.literal(.queryValue(parameters[1].value, type: textType))
        let boundEscape = Expression.literal(.queryValue(.primitive(.null), type: textType))
        let kinds: [PatternMatchKind] = [.like, .caseInsensitiveLike, .similarTo, .regularExpression, .caseInsensitiveRegularExpression]
        for kind in kinds {
            let input = select(.patternMatch(subject: subject, pattern: pattern, escape: kind.permitsEscape ? escape : nil, kind: kind))
            let bound: QueryStatement
            do { bound = try QueryParameterBinder(parameters: parameters).bind(input) }
            catch { throw .binding(error) }
            let expected = select(.patternMatch(subject: boundSubject, pattern: boundPattern,
                escape: kind.permitsEscape ? boundEscape : nil, kind: kind))
            try require(bound == expected && bound.hashValue == expected.hashValue, code: 73)
            try patternRequestRoundTrip(bound)
        }
        let disabled = Expression.patternMatch(subject: boundSubject, pattern: boundPattern, escape: nil, kind: .like)
        let null = Expression.patternMatch(subject: boundSubject, pattern: boundPattern, escape: boundEscape, kind: .like)
        let empty = Expression.patternMatch(subject: boundSubject, pattern: boundPattern, escape: .string(""), kind: .like)
        try require(Set([disabled, null, empty]).count == 3, code: 74)
        let concatenation = Expression.concatenate(boundSubject, boundPattern)
        let boundConcatenation: QueryStatement
        do { boundConcatenation = try QueryParameterBinder(parameters: parameters).bind(select(.concatenate(subject, pattern))) }
        catch { throw .binding(error) }
        try require(boundConcatenation == select(concatenation), code: 75)
        try require(concatenation != .concatenate(boundPattern, boundSubject), code: 75)
        try patternRequestRoundTrip(select(.row([disabled, null, empty, concatenation, .not(disabled)])))
        let counted = Expression.patternMatch(subject: subject, pattern: pattern, escape: escape, kind: .similarTo)
        do { try QueryStructuralValidator.validate(counted, limits: QueryStructuralLimits(maximumTotalNodes: 4)) }
        catch { throw .structure(error) }
        var rejected = false
        do { try QueryStructuralValidator.validate(counted, limits: QueryStructuralLimits(maximumTotalNodes: 3)) }
        catch {
            guard error == .resourceLimitExceeded(resource: .totalNodes, actual: 4, maximum: 3) else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 76)
        rejected = false
        do { try QueryStructuralValidator.validate(.patternMatch(subject: subject, pattern: pattern, escape: escape, kind: .regularExpression)) }
        catch {
            guard error == .invalidPatternEscape else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 77)
        let retainedPattern = Expression.patternMatch(subject: .null, pattern: .string(String(repeating: "x", count: 1000)),
            escape: nil, kind: .like)
        do { try QueryStructuralValidator.validate(retainedPattern, limits: QueryStructuralLimits(maximumRetainedBytes: 1000)) }
        catch { throw .structure(error) }
        for maximum: UInt64 in [999, 100] {
            rejected = false
            do { try QueryStructuralValidator.validate(retainedPattern, limits: QueryStructuralLimits(maximumRetainedBytes: maximum)) }
            catch {
                guard error == .resourceLimitExceeded(resource: .retainedBytes, actual: 1000, maximum: maximum) else { throw .structure(error) }
                rejected = true
            }
            try require(rejected, code: 80)
        }
    }

    private static func patternRequestRoundTrip(_ statement: QueryStatement) throws(Failure) {
        let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(statement) }
        try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) } == statement, code: 78)
        let request = QueryExecuteOperation.Request(input: .statement(statement))
        let frame = try wire { () throws(DatabaseWireError) in
            #if DATABASE_KIT_MULTI_BASE
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 52, target: .database, request: request)
            #else
            try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 52, request: request)
            #endif
        }
        let decoded = try wire { () throws(DatabaseWireError) in try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame) }
        try require(decoded.request == request, code: 79)
    }

    private static func sqlConditionalCarriage() throws(Failure) {
        var nested: Expression = .int(1)
        var different: Expression = .int(2)
        var differentArity: Expression = .row([.int(1), .int(1)])
        for _ in 0..<24 {
            nested = .array([.row([nested])])
            different = .array([.row([different])])
            differentArity = .array([.row([differentArity])])
        }
        let nestedStatement = select(nested)
        let nestedBytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(nestedStatement) }
        let restoredNested = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(nestedBytes) }
        try require(restoredNested == nestedStatement && restoredNested.hashValue == nestedStatement.hashValue, code: 55)
        try require(nested != different && nested != differentArity, code: 56)
        try require(Set([nested, nested, different, differentArity]).count == 3, code: 57)
        let parameter = Expression.parameter(.position(1))
        let typedNull = Expression.literal(.queryValue(.primitive(.null), type: .sql(.integer)))
        func conditional(_ child: Expression) -> Expression {
            .row([
                .caseWhen(operand: child, cases: [CaseWhenPair(condition: .literal(.sqlUnknownString("Exact")), result: child)], elseResult: .null),
                .greatest([child, .null]), .least([.null, child]), .truthTest(child, value: .unknown, negated: true),
                .isDistinctFrom(child, .null, negated: false),
                .quantifiedComparison(child, comparison: .lessThanOrEqual, quantifier: .any, source: .array(child)),
                .quantifiedComparison(child, comparison: .greaterThan, quantifier: .all, source: .subquery(
                    SelectQuery(projection: [ProjectionItem(child)], source: .values([])))),
            ])
        }
        let statement = select(conditional(parameter))
        let bound: QueryStatement
        do {
            let binder = try QueryParameterBinder(parameters: [QueryParameter(position: 1, value: .primitive(.null), type: .sql(.integer))])
            try binder.validate(statement)
            bound = try binder.bind(statement)
        } catch { throw .binding(error) }
        try require(bound == select(conditional(typedNull)), code: 50)
        for original in [statement, bound] {
            let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(original) }
            try require(try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) } == original, code: 51)
            let request = QueryExecuteOperation.Request(input: .statement(original))
            let frame = try wire { () throws(DatabaseWireError) in
                #if DATABASE_KIT_MULTI_BASE
                try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 51, target: .database, request: request)
                #else
                try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 51, request: request)
                #endif
            }
            let decoded = try wire { () throws(DatabaseWireError) in try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame) }
            try require(decoded.request == request, code: 52)
            for end in 0..<bytes.count {
                var rejected = false
                do { _ = try QueryIRWireFormat.decode(ByteString(Array(bytes[0..<end]))) }
                catch { rejected = true }
                try require(rejected, code: 53)
            }
        }
        let simple = Expression.caseWhen(operand: parameter, cases: [CaseWhenPair(condition: parameter, result: parameter)], elseResult: parameter)
        do { try QueryStructuralValidator.validate(simple, limits: QueryStructuralLimits(maximumTotalNodes: 5)) }
        catch { throw .structure(error) }
        var rejected = false
        do { try QueryStructuralValidator.validate(simple, limits: QueryStructuralLimits(maximumTotalNodes: 4)) }
        catch {
            guard error == .resourceLimitExceeded(resource: .totalNodes, actual: 5, maximum: 4) else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 54)
    }

    private static func sqlTemporalValueCarriage() throws(Failure) {
        let zero = try query { () throws(QueryValueError) in try QueryTimeValue(microsecondsSinceMidnight: 0) }
        let endpoint = try query { () throws(QueryValueError) in
            try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000)
        }
        let primitive: FieldValue
        do { primitive = .time(try CivilTime(hour: 0, minute: 0, second: 0)) }
        catch { throw .assertion(180) }
        let values: [QueryValue] = [
            .time(zero), .time(endpoint),
            .timeWithTimeZone(QueryTimeWithTimeZoneValue(time: zero, utcOffsetSeconds: Int32.min)),
            .timeWithTimeZone(QueryTimeWithTimeZoneValue(time: endpoint, utcOffsetSeconds: Int32.max)),
            .dateInfinity(.negative), .dateInfinity(.positive),
            .timestampInfinity(.negative, withTimeZone: false), .timestampInfinity(.positive, withTimeZone: true),
            .intervalInfinity(.negative), .intervalInfinity(.positive), .primitive(primitive),
        ]
        let types: [DataType] = [
            .time(withTimeZone: false), .time(withTimeZone: false, precision: 0),
            .time(withTimeZone: true), .time(withTimeZone: true), .date, .date,
            .timestamp(withTimeZone: false, precision: 3), .timestamp(withTimeZone: true, precision: 6),
            .interval(fields: .year), .interval(fields: .dayToSecond, precision: 3), .time(withTimeZone: false),
        ]
        var columns: [QueryColumn] = []
        for index in values.indices {
            let payload = try query { () throws(QueryValueError) in
                try QueryFieldStorageAdapter.encode(values[index], type: .sql(types[index]), limits: limits)
            }
            let restored = try query { () throws(QueryValueError) in
                try QueryFieldStorageAdapter.decode(payload, type: .sql(types[index]), limits: limits)
            }
            try require(restored == values[index], code: 181)
            columns.append(try query { () throws(QueryValueError) in
                try QueryColumn(number: UInt32(index + 1), name: "temporal", type: .sql(types[index]), isNullable: false)
            })
        }
        try require(values[0] != values[10], code: 182)
        try require(values[0] != values[1], code: 183)
        let expected = QueryRow(values: values)
        let retained = try retainedPage(columns: columns, rows: [expected])
        var iterator = retained.makeRowIterator()
        try require(try wire { () throws(DatabaseWireError) in try iterator.next() } == expected, code: 184)
        try require(retained.columns == columns, code: 185)
        try rejectQuery(.timeOutOfRange, code: 186) { () throws(QueryValueError) in
            _ = try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_001)
        }
        try require(!QueryValueValidator.accepts(.primitive(.null),
            type: .sql(.interval(fields: .day, precision: 3))), code: 187)
        let measured = try query { () throws(QueryValueError) in try QueryValueValidator.measure(.time(endpoint)) }
        try require(measured.nodeCount == 1 && measured.retainedByteCount == 0, code: 188)
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

    /// Extends the existing constructor case without changing harness markers.
    private static func sqlCollectionCarriage() throws(Failure) {
        let input = try query { () throws(QueryValueError) in
            try QueryArrayInput(sqlLexicalForm: #"[-1:1]={NULL,"NULL",a\,b}"#, limits: limits)
        }
        try require(input.count == 3 && input.dimensions[0].lowerBound == -1, code: 190)
        let texts = try query { () throws(QueryValueError) in
            (try input.elementText(at: 0), try input.elementText(at: 1), try input.elementText(at: 2))
        }
        try require(texts.0 == nil && texts.1 == "NULL" && texts.2 == "a,b", code: 191)
        let whitespace = try query { () throws(QueryValueError) in
            let value = try QueryArrayInput(sqlLexicalForm: #"{x\  ,\ ,  a  }"#, limits: limits)
            return (try value.elementText(at: 0), try value.elementText(at: 1), try value.elementText(at: 2))
        }
        try require(whitespace.0 == "x " && whitespace.1 == " " && whitespace.2 == "a", code: 202)
        try rejectQuery(.invalidArrayInputIndex(index: 3, count: 3), code: 192) {
            () throws(QueryValueError) in _ = try input.elementText(at: 3)
        }
        let exact = QueryValueLimits(maximumRetainedBytes: input.retainedByteCount, maximumTotalNodes: 4,
            maximumNestingDepth: 2, maximumCollectionElements: 3)
        _ = try query { () throws(QueryValueError) in
            try QueryArrayInput(sqlLexicalForm: #"[-1:1]={NULL,"NULL",a\,b}"#, limits: exact)
        }
        let root = try query { () throws(QueryValueError) in
            var builder = try QueryJSONBBuilder(limits: limits, nodeCapacity: 513, elementIndexCapacity: 512, memberCapacity: 0)
            var child = try builder.append(.string("leaf"))
            for _ in 0..<512 { child = try builder.appendArray([child]) }
            return try builder.finish(root: child)
        }
        var leaf = root
        for _ in 0..<512 {
            guard case .array(let children) = leaf else { throw .assertion(193) }
            leaf = children[0]
        }
        try require(leaf == .string("leaf"), code: 194)
        try rejectQuery(.resourceLimit(resource: "jsonbPlannedNodeCapacity", actual: 1, maximum: 0), code: 195) {
            () throws(QueryValueError) in
            var builder = try QueryJSONBBuilder(limits: limits, nodeCapacity: 0, elementIndexCapacity: 0, memberCapacity: 0)
            _ = try builder.append(.null)
        }
        let parameter = QueryParameter(position: 1, value: .primitive(.int64(1)))
        let grouped = Expression.arrayAccess(.parameter(.position(1)), subscripts: [
            .index(.parameter(.position(1))), .slice(lower: nil, upper: .parameter(.position(1))),
        ])
        for byte in UInt8(0)...10 {
            guard let operation = CollectionOperator(rawValue: byte) else { throw .assertion(196) }
            let expression = Expression.collectionOperation(operation, left: grouped,
                right: .function(FunctionCall(name: "f", arguments: [.parameter(.position(1))],
                    schema: "s", finalArrayIsVariadic: true)))
            let bound: QueryStatement
            do { bound = try QueryParameterBinder(parameters: [parameter]).bind(select(expression)) }
            catch { throw .binding(error) }
            try patternRequestRoundTrip(bound)
            let bytes = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(bound) }
            let restored = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.decode(bytes) }
            try require(restored == bound && restored.hashValue == bound.hashValue, code: 197)
        }
        var rejected = false
        do {
            try QueryStructuralValidator.validate(.function(FunctionCall(name: "f", arguments: [], finalArrayIsVariadic: true)))
        } catch {
            guard error == .emptyVariadicFunctionArguments else { throw .structure(error) }
            rejected = true
        }
        try require(rejected, code: 198)
        let variadic = select(.function(FunctionCall(name: "f", arguments: [.null], finalArrayIsVariadic: true)))
        let encoded = try wire { () throws(DatabaseWireError) in try QueryIRWireFormat.encode(variadic) }
        // This bounded fixture contains no byte55 in names or preceding counts.
        // Corrupt the actual new production's hasSchema Boolean, then its count.
        guard let tag = encoded.firstIndex(of: 55) else { throw .assertion(199) }
        var invalid = Array(encoded)
        invalid[tag + 1] = 2
        let invalidBoolean = ByteString(invalid)
        try rejectWire(.invalidBool(2), code: 200) { () throws(DatabaseWireError) in
            _ = try QueryIRWireFormat.decode(invalidBoolean)
        }
        invalid = Array(encoded)
        // Tag, hasSchema, String length and one-byte name precede UInt32 count.
        for offset in 7..<11 { invalid[tag + offset] = 0 }
        let emptyVariadic = ByteString(invalid)
        try rejectWire(.invalidQueryIRWireState, code: 201) { () throws(DatabaseWireError) in
            _ = try QueryIRWireFormat.decode(emptyVariadic)
        }
    }

    private static func sqlConstructorsAndTemporalDescriptors() throws(Failure) {
        try sqlCollectionCarriage()
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
                    let request = QueryExecuteOperation.Request(input: .statement(statement), parameters: [parameter])
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
        .select(SelectQuery(projection: [ProjectionItem(expression)], source: .values([])))
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

    private static func rejectQuery(_ expected: QueryValueError, code: UInt8,
                                    _ body: () throws(QueryValueError) -> Void) throws(Failure) {
        var rejected = false
        do { try body() }
        catch {
            guard error == expected else { throw .query(error) }
            rejected = true
        }
        try require(rejected, code: code)
    }

    private static func query<Value>(_ body: () throws(QueryValueError) -> Value) throws(Failure) -> Value {
        do { return try body() } catch { throw .query(error) }
    }

    private static func catalog<Value>(_ body: () throws(SQLCatalogError) -> Value) throws(Failure) -> Value {
        do { return try body() } catch { throw .catalog(error) }
    }

    private static func rejectCatalog(_ expected: SQLCatalogError, code: UInt8,
                                      _ body: () throws(SQLCatalogError) -> Void) throws(Failure) {
        var rejected = false
        do { try body() }
        catch {
            guard error == expected else { throw .catalog(error) }
            rejected = true
        }
        try require(rejected, code: code)
    }

    private static func wire<Value>(_ body: () throws(DatabaseWireError) -> Value) throws(Failure) -> Value {
        do { return try body() } catch { throw .wire(error) }
    }

    private static func require(_ condition: Bool, code: UInt8) throws(Failure) {
        guard condition else { throw .assertion(code) }
    }

    private static func pass(_ name: String) { print("QUERY_VALUE_RUNTIME_CASE \(name) PASS") }
}
