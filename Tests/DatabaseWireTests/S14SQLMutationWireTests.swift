import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("S14 SQL mutation Wire carriage")
struct S14SQLMutationWireTests {
    private let aliases = SQLReturningAliases(old: "prior", new: "next")

    private func limits(frame: Int = 100_000, string: Int = 1000,
                        collection: Int = 1000, depth: Int = 512, objects: Int = 100_000) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string,
            maximumByteStringBytes: frame, maximumCollectionCount: collection,
            maximumNestingDepth: depth, maximumObjectCount: objects)
    }

    private func roundTrip(_ statement: QueryStatement) throws {
        let bytes = try QueryIRWireFormat.encode(statement)
        #expect(try QueryIRWireFormat.decode(bytes) == statement)
        var count = 0
        var streamed: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(statement,
            prepare: { count = $0 }, consume: { streamed.append(contentsOf: $0) })
        #expect(count == bytes.count)
        #expect(ByteString(streamed) == bytes)
    }

    private func mixedStatement() -> QueryStatement {
        let update = QueryStatement.update(UpdateQuery(target: TableRef("target"),
            assignments: [Assignment(columns: ["a", "b"], value: .row([.parameter(position: 1), .defaultValue]))],
            returning: [.wildcard(qualifier: "next")], returningAliases: aliases))
        return .with(SQLWithStatement(recursive: true, statements: [
            SQLNamedStatement(name: "changed", columns: ["a", "b"], statement: update,
                materialized: .notMaterialized,
                search: CTESearchClause(order: .breadthFirst, columns: ["a"], sequenceColumn: "sequence"),
                cycle: CTECycleClause(columns: ["a"], markColumn: "cycle", pathColumn: "path",
                    markValue: .bool(true), defaultValue: .bool(false))),
        ], body: .delete(DeleteQuery(target: TableRef("target"), filter: .parameter(name: "filter"),
            returning: [.wildcard(qualifier: "prior")], returningAliases: aliases))))
    }

    @Test("WITH metadata tuple RHS aliases and parameter occurrences survive canonical carriage")
    func mixedWithRoundTrip() throws {
        try roundTrip(mixedStatement())
    }

    @Test("WITH has fixed metadata-before-child order and recursive presence")
    func withGolden() throws {
        let leaf = QueryStatement.truncate(TruncateQuery(tables: [TableRef("t")]))
        let statement = QueryStatement.with(SQLWithStatement(recursive: true,
            statements: [SQLNamedStatement(name: "cte", columns: ["a"], statement: leaf, materialized: .materialized)], body: leaf))
        let expected = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(10)
            writer.writeBool(true)
            try writer.writeCount(1)
            try writer.writeString("cte")
            writer.writeBool(true)
            try writer.writeCount(1)
            try writer.writeString("a")
            writer.writeBool(true)
            writer.writeUInt8(0)
            writer.writeBool(false)
            writer.writeBool(false)
            for _ in 0..<2 {
                writer.writeUInt8(12)
                try writer.writeCount(1)
                try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                writer.writeUInt8(0)
                writer.writeUInt8(0)
            }
        }
        #expect(try QueryIRWireFormat.encode(statement) == expected)
        try roundTrip(statement)
    }

    @Test("MERGE match and action tags have exact deterministic ordered payloads")
    func mergeDiscriminators() throws {
        let matches: [(SQLMergeMatch, UInt8)] = [(.matched, 0), (.notMatchedByTarget, 1), (.notMatchedBySource, 2)]
        let actions: [(SQLMergeAction, UInt8)] = [
            (.insert(columns: nil, values: nil, overriding: nil), 0),
            (.update([Assignment(column: "a", value: .defaultValue)]), 1),
            (.delete, 2), (.doNothing, 3),
        ]
        for (match, matchTag) in matches {
            for (action, actionTag) in actions {
                let statement = QueryStatement.merge(MergeQuery(target: TableRef("t"), source: .values([]),
                    condition: .defaultValue, clauses: [SQLMergeClause(match: match, action: action)]))
                let expected = try DatabaseWireWriter.encode {
                    (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    writer.writeUInt8(11)
                    try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                    try QueryIRWireFormat.encodeDataSource(.values([]), into: &writer)
                    writer.writeUInt8(63)
                    try writer.writeCount(1)
                    writer.writeUInt8(matchTag)
                    writer.writeBool(false)
                    writer.writeUInt8(actionTag)
                    switch actionTag {
                    case 0:
                        writer.writeBool(false)
                        writer.writeBool(false)
                        writer.writeUInt8(0)
                    case 1:
                        try writer.writeCount(1)
                        try writer.writeCount(1)
                        try writer.writeString("a")
                        writer.writeUInt8(63)
                    default: break
                    }
                    writer.writeBool(false)
                    writer.writeBool(false)
                }
                #expect(try QueryIRWireFormat.encode(statement) == expected)
                try roundTrip(statement)
            }
        }
    }

    @Test("MERGE INSERT preserves explicit values identity overrides and RETURNING aliases")
    func mergeInsertRoundTrip() throws {
        for overriding: SQLIdentityOverride? in [nil, .systemValue, .userValue] {
            try roundTrip(.merge(MergeQuery(target: TableRef("t"), source: .values([[.int(1)]]), condition: .bool(true),
                clauses: [SQLMergeClause(match: .notMatchedByTarget, condition: .parameter(position: 1),
                    action: .insert(columns: ["a"], values: [.defaultValue], overriding: overriding))],
                returning: [.wildcard()], returningAliases: aliases)))
        }
    }

    @Test("TRUNCATE has fixed statement identity and reference bytes")
    func truncateGolden() throws {
        for (identity, identityTag): (SQLTruncateIdentity, UInt8) in [(.continue, 0), (.restart, 1)] {
            for (references, referencesTag): (SQLTruncateReferences, UInt8) in [(.restrict, 0), (.cascade, 1)] {
                let statement = QueryStatement.truncate(TruncateQuery(tables: [TableRef("t")], identity: identity, references: references))
                let expected = try DatabaseWireWriter.encode {
                    (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    writer.writeUInt8(12)
                    try writer.writeCount(1)
                    try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                    writer.writeUInt8(identityTag)
                    writer.writeUInt8(referencesTag)
                }
                #expect(try QueryIRWireFormat.encode(statement) == expected)
                try roundTrip(statement)
            }
        }
    }

    @Test("Conflict target and INSERT tails have closed tags and preserve inference expressions")
    func insertConflictTails() throws {
        for (target, tag): (SQLConflictTarget, UInt8) in [(.columns(["a"], where: .parameter(position: 1)), 0), (.constraint("unique_a"), 1)] {
            let base = QueryStatement.insert(InsertQuery(target: TableRef("t"), source: .defaultValues,
                onConflict: .doNothing, returning: [.wildcard()], overriding: .userValue))
            let statement = QueryStatement.insert(InsertQuery(target: TableRef("t"), source: .defaultValues,
                onConflict: .doNothing, returning: [.wildcard()], overriding: .userValue,
                conflictTarget: target, returningAliases: aliases))
            let tail = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeBool(true)
                writer.writeUInt8(tag)
                switch target {
                case .columns(let names, let predicate):
                    try QueryIRWireFormat.writeStrings(names, into: &writer)
                    try QueryIRWireFormat.writeOptional(predicate, into: &writer, encode: QueryIRWireFormat.encodeExpression)
                case .constraint(let name): try writer.writeString(name)
                }
                writer.writeBool(true)
                try QueryIRWireFormat.writeOptionalString("prior", into: &writer)
                try QueryIRWireFormat.writeOptionalString("next", into: &writer)
            }
            let prefix = try QueryIRWireFormat.encode(base)
            #expect(try QueryIRWireFormat.encode(statement) == ByteString(Array(prefix[0..<(prefix.count - 2)]) + Array(tail)))
            try roundTrip(statement)
        }
    }

    @Test("Every truncated mixed statement prefix and trailing bytes fail explicitly")
    func truncationAndTrailingInput() throws {
        for statement in [mixedStatement(), .merge(MergeQuery(target: TableRef("t"), source: .values([]),
            condition: .bool(true), clauses: [SQLMergeClause(match: .matched, action: .delete)])),
            .truncate(TruncateQuery(tables: [TableRef("t")]))] {
            let bytes = try QueryIRWireFormat.encode(statement)
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString(Array(bytes[0..<end]))) }
            }
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString(Array(bytes) + [0])) }
        }
    }

    @Test("Unknown statement enums malformed WITH Bool and optional tags fail typed")
    func unknownAndMalformedTags() throws {
        #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString([255])) }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString([10, 2])) }
        let truncate = try QueryIRWireFormat.encode(.truncate(TruncateQuery(tables: [TableRef("t")])))
        for offset in [truncate.count - 2, truncate.count - 1] {
            var invalid = Array(truncate)
            invalid[offset] = 255
            #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString(invalid)) }
        }
        let merge = try QueryIRWireFormat.encode(.merge(MergeQuery(target: TableRef("t"), source: .values([]),
            condition: .defaultValue, clauses: [SQLMergeClause(match: .matched, action: .delete)])))
        for offset in [merge.count - 5, merge.count - 3] {
            var invalid = Array(merge)
            invalid[offset] = 255
            #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString(invalid)) }
        }
        let insert = try QueryIRWireFormat.encode(.insert(InsertQuery(target: TableRef("t"), source: .defaultValues)))
        for offset in [insert.count - 2, insert.count - 1] {
            var invalid = Array(insert)
            invalid[offset] = 2
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString(invalid)) }
        }
    }

    @Test("Invalid intrinsic mutation shape fails before prepare and sink emission")
    func invalidShapeHasNoEmission() throws {
        var statements: [QueryStatement] = [
            .truncate(TruncateQuery(tables: [])),
            .with(SQLWithStatement(statements: [], body: .truncate(TruncateQuery(tables: [TableRef("t")])))),
            .update(UpdateQuery(target: TableRef("t"), assignments: [Assignment(columns: [], value: .defaultValue)])),
            .merge(MergeQuery(target: TableRef("t"), source: .values([]), condition: .bool(true), clauses: [
                SQLMergeClause(match: .notMatchedByTarget, action: .insert(columns: nil, values: [], overriding: nil)),
            ])),
            .delete(DeleteQuery(target: TableRef("t"), returningAliases: SQLReturningAliases(old: "old"))),
        ]
        let select = QueryStatement.select(SelectQuery(projection: [.expression(.int(1))], source: .values([])))
        for definition in [
            SQLNamedStatement(name: "q", columns: ["a"], statement: select,
                search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "a")),
            SQLNamedStatement(name: "q", columns: ["a"], statement: select,
                cycle: CTECycleClause(columns: ["k"], markColumn: "a", pathColumn: "p")),
            SQLNamedStatement(name: "q", statement: select,
                search: CTESearchClause(order: .depthFirst, columns: ["k"], sequenceColumn: "m"),
                cycle: CTECycleClause(columns: ["k"], markColumn: "m", pathColumn: "p")),
        ] {
            statements.append(.with(SQLWithStatement(statements: [definition], body: .delete(DeleteQuery(target: TableRef("t"))))))
        }
        for statement in statements {
            var prepared = false
            var emitted = 0
            #expect(throws: DatabaseWireEmissionError<Never>.self) {
                try QueryIRWireFormat.emitCanonicalEncoding(statement,
                    prepare: { _ in prepared = true }, consume: { emitted += $0.count })
            }
            #expect(!prepared)
            #expect(emitted == 0)
        }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString([12, 0, 0, 0, 0, 0, 0])) }
    }

    @Test("Deep WITH uses shared frame string collection object and nesting limits")
    func sharedLimits() throws {
        var statement = QueryStatement.truncate(TruncateQuery(tables: [TableRef("table")]))
        for _ in 0..<100 {
            statement = .with(SQLWithStatement(statements: [SQLNamedStatement(name: "cte", statement:
                .delete(DeleteQuery(target: TableRef("table"))))], body: statement))
        }
        let encoded = try QueryIRWireFormat.encode(statement, limits: limits())
        #expect(try QueryIRWireFormat.decode(encoded, limits: limits()) == statement)
        #expect(try QueryIRWireFormat.encode(statement, limits: limits(frame: encoded.count)) == encoded)
        #expect(try QueryIRWireFormat.decode(encoded, limits: limits(frame: encoded.count)) == statement)
        for restricted in [try limits(frame: encoded.count - 1), try limits(string: 4),
                           try limits(collection: 0), try limits(depth: 100), try limits(objects: 100)] {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(statement, limits: restricted) }
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(encoded, limits: restricted) }
            var emitted = 0
            #expect(throws: DatabaseWireEmissionError<Never>.self) {
                try QueryIRWireFormat.emitCanonicalEncoding(statement, limits: restricted,
                    prepare: { _ in }, consume: { emitted += $0.count })
            }
            #expect(emitted == 0)
        }
    }
}
