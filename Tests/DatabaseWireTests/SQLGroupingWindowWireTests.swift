import DatabaseTypes
import DatabaseKit
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("SQL grouping, aggregate and window Wire carriage")
struct SQLGroupingWindowWireTests {
    @Test("GROUPING and SQL aggregate have deterministic exact bytes")
    func aggregateAndGroupingGoldens() throws {
        let grouping = Expression.grouping([.wholeRow("x")])
        #expect(try encode(grouping) == ByteString([61, 1, 0, 0, 0, 58, 1, 0, 0, 0, 120]))
        let call = SQLAggregateCall(function: .count, arguments: [])
        let golden: [UInt8] = [27, 8, 5, 0, 0, 0, 99, 111, 117, 110, 116, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(try encode(.aggregate(.sql(call))) == ByteString(golden))
        let aggregateBytes = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeAggregate(.sql(call), into: &writer)
        }
        #expect(aggregateBytes == ByteString(golden.dropFirst()))
        var reader = DatabaseWireReader(aggregateBytes)
        #expect(try QueryIRWireFormat.decodeAggregate(from: &reader) == .sql(call))
        try reader.ensureFullyRead()
    }

    @Test("Named OVER has exact bytes and differs from inherited specifications")
    func namedWindowGoldenAndIdentity() throws {
        let function = WindowFunction.analytic(.rank, arguments: [])
        let named = Expression.window(WindowCall(function: function, reference: .named("w")))
        #expect(try encode(named) == ByteString([62, 1, 4, 0, 0, 0, 114, 97, 110, 107,
            0, 0, 0, 0, 0, 1, 0, 0, 0, 119]))
        let inherited = Expression.window(WindowCall(function: function,
            reference: .specification(WindowSpecification(inheritedName: "w"))))
        #expect(try encode(named) != encode(inherited))
        try roundTrip(named)
        try roundTrip(inherited)
        let explicit = Expression.window(WindowCall(function: function, reference: .specification(
            WindowSpecification(frame: WindowFrame(mode: .rows, start: .unboundedPreceding, end: .currentRow)))))
        #expect(try encode(explicit) == ByteString([62, 1, 4, 0, 0, 0, 114, 97, 110, 107,
            0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 2, 0]))
    }

    @Test("Every closed aggregate and analytic function preserves exact schema and children")
    func everyFunctionRoundTrips() throws {
        for function in SQLAggregateFunction.allCases {
            let call = SQLAggregateCall(function: function,
                arguments: [.parameter(.name("arg")), .wholeRow("x")], distinct: true,
                orderBy: [SortKey(.parameter(.name("sort")), direction: .descending, nulls: .last)],
                filter: .parameter(.name("filter")),
                withinGroup: [SortKey(.parameter(.name("within")), nulls: .first)], schema: "ExactSchema")
            try roundTrip(.aggregate(.sql(call)))
            try roundTrip(.window(WindowCall(function: .aggregate(call), reference: .named("w"))))
        }
        for function in SQLWindowFunction.allCases {
            try roundTrip(.window(WindowCall(function: .analytic(function,
                arguments: [.parameter(.position(1)), .parameter(.position(2))]),
                reference: .specification(specification()))))
        }
    }

    @Test("Grouping units, duplicates and empty grouping sets survive the SELECT envelope")
    func groupingAndNamedWindowsRoundTrip() throws {
        let emptySet = SelectQuery(projection: [], source: .values([]), groupBy: [.groupingSets([[]])])
        let golden: [UInt8] = [0, 0, 0, 0, 0, 0, 14, 0, 0, 0, 0,
            0, 0, 1, 1, 0, 0, 0, 3, 1, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        #expect(try QueryIRWireFormat.encode(.select(emptySet)) == ByteString(golden))
        let x = Expression.parameter(.name("x"))
        let grouping: [GroupingElement] = [.expression(x), .rollup([[x, .int(1)], []]),
            .cube([[x], [x, .int(2)]]), .groupingSets([[], [.expression(x)], [.expression(x)],
                [.groupingSets([[.cube([[x]])]])]])]
        let query = SelectQuery(projection: [.expression(.grouping([x]))], source: .values([[]]),
            groupBy: grouping, having: .bool(true), windows: [NamedWindow(name: "w", specification: specification())])
        let bytes = try QueryIRWireFormat.encode(.select(query))
        #expect(try QueryIRWireFormat.decode(bytes) == .select(query))
        var streamed: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(.select(query), prepare: { _ in }, consume: { streamed.append(contentsOf: $0) })
        #expect(ByteString(streamed) == bytes)
        let base = SelectQuery(projection: [.wildcard()], source: .values([[]]))
        #expect(try QueryIRWireFormat.encode(.select(base)) != QueryIRWireFormat.encode(.select(base.replacing(groupBy: []))))
        #expect(try QueryIRWireFormat.encode(.select(base.replacing(groupBy: []))) != QueryIRWireFormat.encode(.select(base.replacing(groupBy: [.groupingSets([[]])]))))
    }

    @Test("All frame bounds, modes and exclusions retain absent versus explicit frames")
    func framesRoundTrip() throws {
        let bounds: [WindowFrameBound] = [.unboundedPreceding, .preceding(.parameter(.name("start"))),
            .currentRow, .following(.parameter(.name("end"))), .unboundedFollowing]
        let function = WindowFunction.analytic(.rowNumber, arguments: [])
        let absent = Expression.window(WindowCall(function: function, reference: .specification(WindowSpecification())))
        for mode: WindowFrameMode in [.rows, .range, .groups] {
            for exclusion: WindowFrameExclusion in [.noOthers, .currentRow, .group, .ties] {
                for bound in bounds {
                    let expression = Expression.window(WindowCall(function: function, reference: .specification(
                        WindowSpecification(frame: WindowFrame(mode: mode, start: bound, end: bound, exclusion: exclusion)))))
                    #expect(try encode(expression) != encode(absent))
                    try roundTrip(expression)
                }
            }
        }
        for within: [SortKey]? in [nil, []] {
            try roundTrip(.aggregate(.sql(SQLAggregateCall(function: .mode, arguments: [], withinGroup: within))))
        }
        #expect(try encode(.aggregate(.sql(SQLAggregateCall(function: .mode, arguments: [])))) !=
            encode(.aggregate(.sql(SQLAggregateCall(function: .mode, arguments: [], withinGroup: [])))))
    }

    @Test("Every truncated prefix and trailing byte rejects without partial publication")
    func truncatedAndTrailingReject() throws {
        let query = SelectQuery(projection: [.expression(.window(WindowCall(function: .aggregate(
            SQLAggregateCall(function: .sum, arguments: [.int(1)], distinct: true, orderBy: [SortKey(.int(2))],
                filter: .bool(true), withinGroup: [], schema: "pg_catalog")), reference: .specification(specification()))))],
            source: .values([[]]), groupBy: [.groupingSets([[], [.rollup([[.int(1)]])]])],
            windows: [NamedWindow(name: "w", specification: specification())])
        let bytes = Array(try QueryIRWireFormat.encode(.select(query)))
        for count in 0..<bytes.count {
            #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decode(ByteString(bytes.prefix(count))) }
        }
        #expect(throws: DatabaseWireError.trailingBytes) { _ = try QueryIRWireFormat.decode(ByteString(bytes + [0])) }
    }

    @Test("Unknown tags, function names, strict flags and grouping tags reject")
    func malformedMetadataRejects() throws {
        let unknownFunction: [UInt8] = [27, 8, 1, 0, 0, 0, 63]
        for bytes: [UInt8] in [[62, 2], [62, 1, 1, 0, 0, 0, 63], unknownFunction,
            [62, 1, 4, 0, 0, 0, 114, 97, 110, 107, 0, 0, 0, 0, 2],
            [27, 8, 5, 0, 0, 0, 99, 111, 117, 110, 116, 2]] {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(bytes)
                _ = try QueryIRWireFormat.decodeExpression(from: &reader)
            }
        }
        let framed = Expression.window(WindowCall(function: .analytic(.rank, arguments: []),
            reference: .specification(WindowSpecification(frame: WindowFrame(mode: .rows,
                start: .unboundedPreceding, end: .currentRow)))))
        let validFrame = Array(try encode(framed))
        for (offset, invalid): (Int, UInt8) in [(5, 2), (4, 3), (3, 5), (2, 5), (1, 4)] {
            var corrupted = validFrame
            corrupted[corrupted.count - offset] = invalid
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(corrupted)
                _ = try QueryIRWireFormat.decodeExpression(from: &reader)
            }
        }
        let query = SelectQuery(projection: [], source: .values([]), groupBy: [.expression(.int(1))])
        var bytes = Array(try QueryIRWireFormat.encode(.select(query)))
        // Statement, CTE flag, empty projection, empty VALUES, access/filter, grouping flag/count.
        bytes[18] = 255
        #expect(throws: DatabaseWireError.invalidValueTag(255)) { _ = try QueryIRWireFormat.decode(ByteString(bytes)) }
    }

    @Test("Deep grouping and window offsets share count, object and nesting quotas")
    func structuralBudgetsReject() throws {
        var grouping = GroupingElement.expression(.int(1))
        for _ in 0..<64 { grouping = .groupingSets([[grouping]]) }
        let query = SelectQuery(projection: [], source: .values([[]]), groupBy: [grouping],
            windows: [NamedWindow(name: "w", specification: specification())])
        // Statement + SELECT + 65 grouping nodes + Expression + Literal scopes.
        let exactDepth = 69
        let roomy = try self.limits(depth: exactDepth)
        let bytes = try QueryIRWireFormat.encode(.select(query), limits: roomy)
        #expect(try QueryIRWireFormat.decode(bytes, limits: roomy) == .select(query))
        let limits = try self.limits(depth: exactDepth - 1)
        #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.encode(.select(query), limits: limits) }
        #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decode(bytes, limits: limits) }
        let exactFrame = try self.limits(depth: exactDepth, frame: bytes.count)
        #expect(try QueryIRWireFormat.encode(.select(query), limits: exactFrame) == bytes)
        #expect(try QueryIRWireFormat.decode(bytes, limits: exactFrame) == .select(query))
        let shortFrame = try self.limits(depth: exactDepth, frame: bytes.count - 1)
        #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.encode(.select(query), limits: shortFrame) }
        #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decode(bytes, limits: shortFrame) }
        let countLimits = try self.limits(count: 1)
        #expect(try encode(.grouping([.int(1)]), limits: countLimits) == encode(.grouping([.int(1)])))
        #expect(throws: DatabaseWireError.self) {
            _ = try encode(.grouping([.int(1), .int(2)]), limits: countLimits)
        }
        let objectLimits = try self.limits(objects: 8)
        #expect(throws: DatabaseWireError.self) { _ = try QueryIRWireFormat.decode(bytes, limits: objectLimits) }
    }

    private func limits(depth: Int = 64, count: Int = 65_536, objects: Int = 250_000, frame: Int = 1_048_576) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: 65_536,
            maximumByteStringBytes: 65_536, maximumCollectionCount: count,
            maximumNestingDepth: depth, maximumObjectCount: objects)
    }

    private func specification() -> WindowSpecification {
        WindowSpecification(inheritedName: "parent", partitionBy: [.parameter(.name("partition"))],
            orderBy: [SortKey(.parameter(.name("order")), direction: .descending, nulls: .last)],
            frame: WindowFrame(mode: .rows, start: .preceding(.parameter(.name("start"))),
                end: .following(.parameter(.name("end"))), exclusion: .ties))
    }

    private func encode(_ expression: Expression, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(expression, into: &writer)
        }
    }

    private func roundTrip(_ expression: Expression) throws {
        let bytes = try encode(expression)
        var reader = DatabaseWireReader(bytes)
        #expect(try QueryIRWireFormat.decodeExpression(from: &reader) == expression)
        try reader.ensureFullyRead()
    }
}
