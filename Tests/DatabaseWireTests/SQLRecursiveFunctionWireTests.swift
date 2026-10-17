import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("Recursive CTE and table-function Wire carriage")
struct SQLRecursiveFunctionWireTests {
    @Test("SELECT and SEARCH/CYCLE metadata have exact canonical field order")
    func metadataGoldens() throws {
        let search = CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "s")
        let cycle = CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p")
        let declaration = NamedSubquery(name: "c", query: identity(), search: search, cycle: cycle)
        let metadata: [UInt8] = [1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 107, 1, 0, 0, 0, 115,
            1, 1, 0, 0, 0, 1, 0, 0, 0, 107, 1, 0, 0, 0, 109, 1, 0, 0, 0, 112, 0]
        #expect(try encodeMetadata(declaration) == ByteString(metadata))
        let breadth = NamedSubquery(name: "c", query: identity(),
            search: CTESearchClause(order: .breadthFirst, columns: ["k"], sequenceColumn: "s"), cycle: cycle)
        var breadthGolden = metadata
        breadthGolden[1] = 1
        #expect(try encodeMetadata(breadth) == ByteString(breadthGolden))
        let explicit = NamedSubquery(name: "c", query: identity(), cycle: CTECycleClause(
            columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .bool(true), defaultValue: .bool(false)))
        #expect(try encodeMetadata(explicit) == ByteString([0] + Array(metadata.dropFirst(16).dropLast()) + [1, 1, 1, 1, 0]))
        let base = Array(try QueryIRWireFormat.encode(.select(identity())))
        #expect(base.last == 0)
        #expect(try QueryIRWireFormat.encode(.select(identity().replacing(withRecursive: true)))
            == ByteString(base.dropLast() + [1]))
    }

    @Test("Source18 reuses exact function tags and only the existing alias wrapper")
    func functionSourceGoldens() throws {
        let calls = [FunctionCall(name: "f", arguments: [.null]),
            FunctionCall(name: "f", arguments: [.null], schema: "s"),
            FunctionCall(name: "f", arguments: [.null], finalArrayIsVariadic: true)]
        for call in calls {
            for ordinal in [false, true] {
                let source = DataSource.tableFunction(TableFunctionSource(function: call, withOrdinality: ordinal))
                let expression = try encodeExpression(.function(call))
                let bytes = try encodeSource(source)
                #expect(bytes == ByteString([18, ordinal ? 1 : 0] + Array(expression)))
                try roundTripSource(source)
                let aliased = DataSource.aliased(source, name: "r", columns: ["v", "n"])
                #expect(try encodeSource(aliased) == ByteString([16, 1, 0, 0, 0, 114, 1, 2, 0, 0, 0,
                    1, 0, 0, 0, 118, 1, 0, 0, 0, 110] + Array(bytes)))
                try roundTripSource(aliased)
            }
        }
    }

    @Test("Full and residual declaration paths preserve optional metadata and rich constant owners")
    func fullAndResidualRoundTrips() throws {
        let json = try QueryJSONValue(bytes: ByteString(utf8: " {\"k\":null} "), limits: DatabaseWireLimits.default.queryValueLimits)
        let numeric = try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 2)
        let array = try QueryArrayValue(elementType: .integer, dimensions: [QueryArrayDimension(lowerBound: -2, length: 2)],
            elements: [.primitive(.int32(7)), .primitive(.null)], limits: DatabaseWireLimits.default.queryValueLimits)
        let constants: [Literal] = [.null, .bool(true), .int(7), .sqlUnknownString("Exact"),
            .binary(ByteString([1, 2, 3])), .queryValue(.json(json), type: .sql(.json)), .queryValue(.numeric(numeric)),
            .queryValue(.array(array), type: .sql(.array(.integer)))]
        for constant in constants {
            for order: CTESearchOrder in [.depthFirst, .breadthFirst] {
                let declaration = NamedSubquery(name: "c", columns: ["k"], query: identity(), materialized: .notMaterialized,
                    search: CTESearchClause(order: order, columns: ["k"], sequenceColumn: "s"),
                    cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p",
                        markValue: constant, defaultValue: constant))
                let helper = try encodeDeclaration(declaration)
                var reader = DatabaseWireReader(helper)
                #expect(try QueryIRWireFormat.decodeNamedSubquery(from: &reader) == declaration)
                try reader.ensureFullyRead()
                let query = SelectQuery(projection: [.wildcard()], source: .tableFunction(TableFunctionSource(
                    function: FunctionCall(name: "generate_series", arguments: [.int(1), .parameter(.position(1))]), withOrdinality: true)),
                    subqueries: [declaration], withRecursive: true)
                let bytes = try QueryIRWireFormat.encode(.select(query))
                #expect(Array(bytes.prefix(6 + helper.count)) == [0, 1, 1, 0, 0, 0] + Array(helper))
                #expect(try QueryIRWireFormat.decode(bytes) == .select(query))
                var streamed: [UInt8] = []
                try QueryIRWireFormat.emitCanonicalEncoding(.select(query), prepare: { #expect($0 == bytes.count) },
                    consume: { streamed.append(contentsOf: $0) })
                #expect(ByteString(streamed) == bytes)
            }
        }
        let absent = NamedSubquery(name: "c", query: identity())
        #expect(Array(try encodeDeclaration(absent).suffix(3)) == [0, 0, 0])
    }

    @Test("Every truncated prefix and trailing byte rejects before a query is published")
    func truncationAndTrailingReject() throws {
        let declaration = sampleDeclaration()
        let query = SelectQuery(projection: [.wildcard()], source: .tableFunction(TableFunctionSource(
            function: FunctionCall(name: "unnest", arguments: [.array([.int(1)])]), withOrdinality: true)),
            subqueries: [declaration], withRecursive: true)
        let bytes = try QueryIRWireFormat.encode(.select(query))
        for count in 0..<bytes.count {
            #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decode(bytes.prefix(count)) }
        }
        #expect(throws: DatabaseWireError.trailingBytes) { _ = try QueryIRWireFormat.decode(ByteString(Array(bytes) + [0])) }
        let helper = try encodeDeclaration(declaration)
        for count in 0..<helper.count {
            var reader = DatabaseWireReader(helper.prefix(count))
            #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decodeNamedSubquery(from: &reader) }
            #expect(reader.currentNestingDepth == 0)
        }
    }

    @Test("Unknown tags, strict flags and non-function source payloads preserve typed failures")
    func malformedMetadataRejects() throws {
        let cases: [(ByteString, DatabaseWireError)] = [
            ([19], .invalidValueTag(19)), ([18, 2], .invalidBool(2)),
            ([18, 0, 255], .invalidValueTag(255)), ([18, 0, 0, 0], .invalidQueryIRWireState),
        ]
        for (bytes, expected) in cases {
            var reader = DatabaseWireReader(bytes)
            #expect(throws: expected) { _ = try QueryIRWireFormat.decodeDataSource(from: &reader) }
            #expect(reader.currentNestingDepth == 0)
        }
        for (bytes, expected): (ByteString, DatabaseWireError) in [
            ([2], .invalidBool(2)), ([1, 255], .invalidValueTag(255)), ([0, 2], .invalidBool(2)),
        ] {
            var reader = DatabaseWireReader(bytes)
            #expect(throws: expected) { _ = try QueryIRWireFormat.decodeCTEMetadata(from: &reader) }
        }
        var bytes = Array(try QueryIRWireFormat.encode(.select(identity())))
        bytes[bytes.count - 1] = 2
        #expect(throws: DatabaseWireError.invalidBool(2)) { _ = try QueryIRWireFormat.decode(ByteString(bytes)) }
    }

    @Test("Intrinsic shape errors reject measured encoding before sink preparation")
    func shapeFailuresRejectBeforeEmission() throws {
        let invalid: [(NamedSubquery, QueryStructuralValidationError)] = [
            (NamedSubquery(name: "c", query: identity(), search: CTESearchClause(order: .depthFirst, columns: [], sequenceColumn: "s")), .invalidCTESearchClause),
            (NamedSubquery(name: "c", query: identity(), cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .bool(true))), .invalidCTECycleClause),
            (NamedSubquery(name: "c", query: identity(), cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .array([]), defaultValue: .array([]))), .invalidCTECycleClause),
        ]
        for (declaration, cause) in invalid {
            let query = identity().replacing(subqueries: [declaration])
            #expect(throws: DatabaseWireError.invalidQueryStructure(cause)) { _ = try encodeDeclaration(declaration) }
            var prepared = false
            var emitted = false
            #expect(throws: DatabaseWireEmissionError<Never>.encoding(.invalidQueryStructure(cause))) {
                try QueryIRWireFormat.emitCanonicalEncoding(.select(query), prepare: { _ in prepared = true }, consume: { _ in emitted = true })
            }
            #expect(!prepared && !emitted)
            if (declaration.cycle?.markValue == nil) == (declaration.cycle?.defaultValue == nil) {
                let raw = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    try writer.writeString(declaration.name)
                    try QueryIRWireFormat.writeOptionalStrings(declaration.columns, into: &writer)
                    try QueryIRWireFormat.encodeSelectQuery(declaration.query, into: &writer)
                    writer.writeBool(false)
                    try QueryIRWireFormat.encodeCTEMetadata(declaration, into: &writer)
                }
                var reader = DatabaseWireReader(raw)
                #expect(throws: DatabaseWireError.invalidQueryStructure(cause)) { _ = try QueryIRWireFormat.decodeNamedSubquery(from: &reader) }
                #expect(reader.currentNestingDepth == 0)
            }
        }
        let source = DataSource.tableFunction(TableFunctionSource(function: FunctionCall(name: "f", arguments: [], distinct: true)))
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidTableFunctionSource)) { _ = try encodeSource(source) }
        let raw = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(18)
            writer.writeBool(false)
            try QueryIRWireFormat.encodeExpression(.function(FunctionCall(name: "f", arguments: [], distinct: true)), into: &writer)
        }
        var reader = DatabaseWireReader(raw)
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidTableFunctionSource)) { _ = try QueryIRWireFormat.decodeDataSource(from: &reader) }
        #expect(reader.currentNestingDepth == 0)
    }

    @Test("Function children and generated metadata share exact and one-past wire budgets")
    func exactAndOnePastBudgets() throws {
        let source = DataSource.tableFunction(TableFunctionSource(function: FunctionCall(name: "func", arguments: [.int(1)])))
        let bytes = try encodeSource(source)
        // Source + function Expression + argument slot + argument Expression + Literal.
        let exact = try limits(frame: bytes.count, string: 4, count: 1, depth: 4, objects: 5)
        #expect(try encodeSource(source, limits: exact) == bytes)
        try roundTripSource(source, limits: exact)
        let rejected = [try limits(frame: bytes.count - 1), try limits(string: 3), try limits(count: 0),
            try limits(depth: 3), try limits(objects: 4)]
        for limit in rejected {
            #expect(throws: DatabaseWireError.self) { _ = try encodeSource(source, limits: limit) }
            var reader = DatabaseWireReader(bytes, limits: limit)
            #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decodeDataSource(from: &reader) }
            #expect(reader.currentNestingDepth == 0)
        }
        let declaration = NamedSubquery(name: "c", query: identity(),
            search: CTESearchClause(order: .depthFirst, columns: ["keys", "more"], sequenceColumn: "seq"))
        let metadata = try encodeDeclaration(declaration, limits: limits(string: 4, count: 2))
        for limit in [try limits(string: 3), try limits(count: 1)] {
            #expect(throws: DatabaseWireError.self) { _ = try encodeDeclaration(declaration, limits: limit) }
            var reader = DatabaseWireReader(metadata, limits: limit)
            #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decodeNamedSubquery(from: &reader) }
        }
    }

    @Test("Deep alternating function/source children retain deterministic identity without stack recursion")
    func deepCarriageAndIndependentOwners() throws {
        func statement() -> QueryStatement {
            var expression = Expression.int(1)
            for _ in 0..<96 { expression = .function(FunctionCall(name: "f", arguments: [expression])) }
            let declaration = NamedSubquery(name: "c", query: identity(), cycle: CTECycleClause(columns: ["k"],
                markColumn: "m", pathColumn: "p", markValue: .binary(ByteString([1, 2, 3])), defaultValue: .null))
            return .select(SelectQuery(projection: [.wildcard()], source: .tableFunction(TableFunctionSource(
                function: FunctionCall(name: "f", arguments: [expression]), withOrdinality: true)), subqueries: [declaration], withRecursive: true))
        }
        let first = statement()
        let second = statement()
        #expect(first == second)
        #expect(first.hashValue == second.hashValue)
        let budget = try limits(depth: 256)
        let bytes = try QueryIRWireFormat.encode(first, limits: budget)
        #expect(try QueryIRWireFormat.encode(second, limits: budget) == bytes)
        #expect(try QueryIRWireFormat.decode(bytes, limits: budget) == first)
    }

    private func identity() -> SelectQuery { SelectQuery(projection: [.wildcard()], source: .values([[]])) }

    private func sampleDeclaration() -> NamedSubquery {
        NamedSubquery(name: "c", query: identity(), materialized: .materialized,
            search: CTESearchClause(order: .breadthFirst, columns: ["k"], sequenceColumn: "s"),
            cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p", markValue: .int(1), defaultValue: .null))
    }

    private func limits(frame: Int = 1_048_576, string: Int = 65_536, count: Int = 65_536,
                        depth: Int = 64, objects: Int = 250_000) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string, maximumByteStringBytes: 65_536,
            maximumCollectionCount: count, maximumNestingDepth: depth, maximumObjectCount: objects)
    }

    private func encodeMetadata(_ declaration: NamedSubquery) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeCTEMetadata(declaration, into: &writer)
        }
    }

    private func encodeDeclaration(_ declaration: NamedSubquery, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeNamedSubquery(declaration, into: &writer)
        }
    }

    private func encodeExpression(_ expression: Expression) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(expression, into: &writer)
        }
    }

    private func encodeSource(_ source: DataSource, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeDataSource(source, into: &writer)
        }
    }

    private func roundTripSource(_ source: DataSource, limits: DatabaseWireLimits = .default) throws {
        var reader = DatabaseWireReader(try encodeSource(source, limits: limits), limits: limits)
        #expect(try QueryIRWireFormat.decodeDataSource(from: &reader) == source)
        try reader.ensureFullyRead()
    }
}
