import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("S15 SQL DDL Wire carriage")
struct S15SQLDDLWireTests {
    private func limits(frame: Int = 1_000_000, string: Int = 1000,
                        collection: Int = 1000, depth: Int = 512, objects: Int = 100_000) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string,
            maximumByteStringBytes: frame, maximumCollectionCount: collection,
            maximumNestingDepth: depth, maximumObjectCount: objects)
    }

    private var query: SelectQuery {
        SelectQuery(projection: [.expression(.parameter(name: "stored"), alias: "e\u{0301}")],
            source: .values([[.int(7)]]), filter: .equal(.int(1), .int(1)))
    }

    private func roundTrip(_ ddl: SQLDDLStatement) throws {
        let statement = QueryStatement.ddl(ddl)
        let bytes = try QueryIRWireFormat.encode(statement)
        #expect(try QueryIRWireFormat.decode(bytes) == statement)
        #expect(try QueryIRWireFormat.encode(statement) == bytes)
        var count = 0
        var streamed: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(statement,
            prepare: { count = $0 }, consume: { streamed.append(contentsOf: $0) })
        #expect(count == bytes.count)
        #expect(ByteString(streamed) == bytes)
    }

    private var declarations: [SQLDDLStatement] {
        [
            .createSchema(name: "é", ifNotExists: true),
            .renameSchema(name: "é", to: "e\u{0301}"),
            .dropSchema(names: ["é", "e\u{0301}"], ifExists: true, behavior: .cascade),
            .createTable(SQLCreateTable(name: TableRef("t"), source: .columns([
                SQLColumnDefinition(name: "a", type: .integer),
            ], constraints: []), temporary: true, ifNotExists: true)),
            .alterTable(SQLAlterTable(name: TableRef("t"), actions: [.renameTable(to: "t2")], ifExists: true)),
            .dropTable(names: [TableRef("t")], ifExists: true, behavior: .cascade),
            .createIndex(SQLCreateIndex(name: TableRef("i"), table: TableRef("t"),
                keys: [SortKey(.col("a"), direction: .descending, nulls: .last)],
                predicate: .parameter(position: 1), unique: true, nulls: .notDistinct, ifNotExists: true)),
            .dropIndex(names: [TableRef("i")], ifExists: true, behavior: .cascade),
            .createView(SQLCreateView(name: TableRef("v"), columns: ["a"], query: query, orReplace: true)),
            .dropView(names: [TableRef("v")], ifExists: true, behavior: .cascade),
            .createMaterializedView(SQLCreateMaterializedView(name: TableRef("m"), columns: ["a"], query: query,
                withData: false, ifNotExists: true)),
            .refreshMaterializedView(name: TableRef("m"), withData: false),
            .dropMaterializedView(names: [TableRef("m")], ifExists: true, behavior: .cascade),
            .createSequence(SQLCreateSequence(name: TableRef("s"), ifNotExists: true)),
            .alterSequence(SQLAlterSequence(name: TableRef("s"), renameTo: "s2", ifExists: true)),
            .dropSequence(names: [TableRef("s")], ifExists: true, behavior: .cascade),
        ]
    }

    @Test("Statement tag13 and all sixteen DDL tags preserve deterministic field order")
    func declarationGoldens() throws {
        for (tag, ddl) in declarations.enumerated() {
            let expected = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(13)
                writer.writeUInt8(UInt8(tag))
                switch tag {
                case 0: try writer.writeString("é"); writer.writeBool(true)
                case 1: try writer.writeString("é"); try writer.writeString("e\u{0301}")
                case 2:
                    try QueryIRWireFormat.writeStrings(["é", "e\u{0301}"], into: &writer)
                    writer.writeBool(true); writer.writeUInt8(1)
                case 3:
                    try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                    writer.writeUInt8(0)
                    try writer.writeCount(1)
                    try writer.writeString("a")
                    try QueryIRWireFormat.encodeDataType(.integer, into: &writer)
                    writer.writeUInt8(0); writer.writeBool(false)
                    try writer.writeCount(0); try writer.writeCount(0)
                    writer.writeBool(true); writer.writeBool(true)
                case 4:
                    try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                    try writer.writeCount(1)
                    writer.writeUInt8(10); try writer.writeString("t2"); writer.writeBool(true)
                case 5, 7, 9, 12, 15:
                    let names = [5: "t", 7: "i", 9: "v", 12: "m", 15: "s"]
                    try writer.writeCount(1)
                    try QueryIRWireFormat.encodeTableRef(TableRef(names[tag]!), into: &writer)
                    writer.writeBool(true); writer.writeUInt8(1)
                case 6:
                    try QueryIRWireFormat.encodeTableRef(TableRef("i"), into: &writer)
                    try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                    try writer.writeCount(1)
                    try QueryIRWireFormat.encodeSortKey(SortKey(.col("a"), direction: .descending, nulls: .last), into: &writer)
                    writer.writeBool(true)
                    try QueryIRWireFormat.encodeExpression(.parameter(position: 1), into: &writer)
                    writer.writeBool(true); writer.writeUInt8(1); writer.writeBool(true)
                case 8, 10:
                    try QueryIRWireFormat.encodeTableRef(TableRef(tag == 8 ? "v" : "m"), into: &writer)
                    try QueryIRWireFormat.writeOptionalStrings(["a"], into: &writer)
                    try QueryIRWireFormat.encodeSelectQuery(query, into: &writer)
                    writer.writeBool(tag == 8)
                    if tag == 10 { writer.writeBool(true) }
                case 11:
                    try QueryIRWireFormat.encodeTableRef(TableRef("m"), into: &writer)
                    writer.writeBool(false)
                case 13, 14:
                    try QueryIRWireFormat.encodeTableRef(TableRef("s"), into: &writer)
                    for _ in 0..<6 { writer.writeBool(false) }
                    writer.writeBool(false)
                    if tag == 14 {
                        writer.writeBool(false)
                        try QueryIRWireFormat.writeOptionalString("s2", into: &writer)
                    }
                    writer.writeBool(true)
                default: throw .invalidQueryIRWireState
                }
            }
            #expect(try QueryIRWireFormat.encode(.ddl(ddl)) == expected)
            try roundTrip(ddl)
        }
    }

    @Test("CTAS view and materialized view retain nested query and explicit metadata")
    func storedQueryRoundTrips() throws {
        for names: [String]? in [nil, ["e\u{0301}"]] {
            for flag in [false, true] {
                try roundTrip(.createTable(SQLCreateTable(name: TableRef(schema: "public", table: "ctas"),
                    source: .query(query, columns: names, withData: flag))))
                try roundTrip(.createView(SQLCreateView(name: TableRef("v"), columns: names, query: query, orReplace: flag)))
                try roundTrip(.createMaterializedView(SQLCreateMaterializedView(name: TableRef("m"), columns: names,
                    query: query, withData: flag, ifNotExists: flag)))
                try roundTrip(.refreshMaterializedView(name: TableRef("m"), withData: flag))
            }
        }
    }

    @Test("Column policy and all constraint metadata retain every expression child")
    func columnAndConstraintRoundTrips() throws {
        let policies: [SQLColumnDefinitionPolicy] = [.input(defaultExpression: nil), .input(defaultExpression: .parameter(name: "d")),
            .generated(.add(.col("a"), .parameter(name: "g")), stored: false),
            .generated(.int(3), stored: true), .identity(generation: .always, options: SQLSequenceOptions(start: 3)),
            .identity(generation: .byDefault, options: SQLSequenceOptions(increment: -1)), .serial]
        let constraints: [SQLTableConstraint] = [
            SQLTableConstraint(name: "pk", kind: .primaryKey(columns: ["a"])),
            SQLTableConstraint(name: "u", timing: .deferrable(initiallyDeferred: true), kind: .unique(columns: ["a"], nulls: .notDistinct)),
            SQLTableConstraint(kind: .unique(columns: ["a"], nulls: .distinct)),
            SQLTableConstraint(kind: .notNull(column: "a")),
            SQLTableConstraint(kind: .check(.greaterThan(.col("a"), .parameter(name: "c")))),
        ]
        for policy in policies {
            try roundTrip(.createTable(SQLCreateTable(name: TableRef("t"), source: .columns([
                SQLColumnDefinition(name: "a", type: .integer, policy: policy, constraints: constraints),
            ], constraints: constraints))))
        }
        let actions: [SQLReferentialAction] = [.noAction, .restrict, .cascade, .setNull, .setDefault]
        for action in actions {
            for match: SQLForeignKeyMatch in [.simple, .full] {
                for names: [String]? in [nil, ["a"]] {
                    let constraint = SQLTableConstraint(name: "fk", timing: .deferrable(initiallyDeferred: false),
                        kind: .foreignKey(SQLForeignKeyDefinition(columns: ["a"], referencedTable: TableRef("target"),
                            referencedColumns: names, match: match, onUpdate: action, onDelete: action,
                            onDeleteColumns: action == .setNull || action == .setDefault ? ["a"] : nil)))
                    try roundTrip(.alterTable(SQLAlterTable(name: TableRef("t"), actions: [.addConstraint(constraint)])))
                }
            }
        }
    }

    @Test("All ALTER actions have fixed tags and preserve source order and optional USING")
    func alterActionRoundTrips() throws {
        let actions: [SQLAlterTableAction] = [
            .addColumn(SQLColumnDefinition(name: "b", type: .text), ifNotExists: true),
            .dropColumn(name: "b", ifExists: true, behavior: .cascade),
            .renameColumn(name: "a", to: "b"), .alterColumnType(name: "b", type: .bigint, using: .parameter(name: "u")),
            .setDefault(column: "b", expression: .parameter(name: "d")), .dropDefault(column: "b"),
            .setNotNull(column: "b"), .dropNotNull(column: "b"),
            .addConstraint(SQLTableConstraint(kind: .check(.parameter(name: "c")))),
            .dropConstraint(name: "c", ifExists: false, behavior: .restrict), .renameTable(to: "renamed"),
        ]
        try roundTrip(.alterTable(SQLAlterTable(name: TableRef("t"), actions: actions)))
        try roundTrip(.alterTable(SQLAlterTable(name: TableRef("t"), actions: [
            .addColumn(SQLColumnDefinition(name: "b", type: .text), ifNotExists: false),
            .dropColumn(name: "b", ifExists: false, behavior: .restrict),
            .alterColumnType(name: "a", type: .integer, using: nil),
            .dropConstraint(name: "c", ifExists: true, behavior: .cascade),
        ])))
        for (tag, action) in actions.enumerated() {
            let bytes = try QueryIRWireFormat.encode(.ddl(.alterTable(SQLAlterTable(name: TableRef("t"), actions: [action]))))
            let prefix = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(13); writer.writeUInt8(4)
                try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                try writer.writeCount(1)
            }
            #expect(bytes[prefix.count] == UInt8(tag))
        }
    }

    @Test("Sequence option absence NO bounds ownership and restart remain distinct")
    func sequenceRoundTrips() throws {
        for type: DataType in [.smallint, .integer, .bigint] {
            try roundTrip(.createSequence(SQLCreateSequence(name: TableRef("typed"), options: SQLSequenceOptions(type: type))))
            try roundTrip(.alterSequence(SQLAlterSequence(name: TableRef("typed"), options: SQLSequenceOptions(type: type, maximum: SQLSequenceBound.none))))
        }
        let options = SQLSequenceOptions(type: .bigint, start: Int64.max, increment: -1,
            minimum: .value(Int64.min), maximum: SQLSequenceBound.none, cycle: false)
        for ownership: SQLSequenceOwnership? in [nil, SQLSequenceOwnership.none, .column(table: TableRef("t"), column: "a")] {
            try roundTrip(.createSequence(SQLCreateSequence(name: TableRef("s"), options: options, ownedBy: ownership)))
            for restart: SQLSequenceRestart? in [nil, .start, .value(Int64.min)] {
                try roundTrip(.alterSequence(SQLAlterSequence(name: TableRef("s"), options: options,
                    restart: restart, ownedBy: ownership, renameTo: "e\u{0301}", ifExists: true)))
            }
        }
        try roundTrip(.createSequence(SQLCreateSequence(name: TableRef("s"),
            options: SQLSequenceOptions(minimum: SQLSequenceBound.none, maximum: .value(100), cycle: true))))
    }

    @Test("Every truncated declaration prefix and trailing byte fails explicitly")
    func malformedPrefixes() throws {
        for ddl in declarations {
            let bytes = try QueryIRWireFormat.encode(.ddl(ddl))
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString(Array(bytes[0..<end]))) }
            }
            #expect(throws: DatabaseWireError.trailingBytes) { try QueryIRWireFormat.decode(ByteString(Array(bytes) + [0])) }
        }
    }

    @Test("Unknown DDL and nested tags strict Booleans and optional presence fail typed")
    func malformedTags() throws {
        #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString([13, 255])) }
        let schema = try QueryIRWireFormat.encode(.ddl(.createSchema(name: "s", ifNotExists: false)))
        var invalid = Array(schema); invalid[invalid.count - 1] = 2
        #expect(throws: DatabaseWireError.invalidBool(2)) { try QueryIRWireFormat.decode(ByteString(invalid)) }
        for ddl in [SQLDDLStatement.dropTable(names: [TableRef("t")], ifExists: false, behavior: .restrict),
                    .dropSchema(names: ["s"], ifExists: false, behavior: .restrict)] {
            var bytes = Array(try QueryIRWireFormat.encode(.ddl(ddl))); bytes[bytes.count - 1] = 255
            #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString(bytes)) }
        }
        let tablePrefix = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(13); writer.writeUInt8(3)
            try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString(Array(tablePrefix) + [255])) }
        let sequencePrefix = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(13); writer.writeUInt8(13)
            try QueryIRWireFormat.encodeTableRef(TableRef("s"), into: &writer)
        }
        #expect(throws: DatabaseWireError.invalidBool(2)) { try QueryIRWireFormat.decode(ByteString(Array(sequencePrefix) + [2])) }
        let columnPrefix = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeCount(1); try writer.writeString("a")
            try QueryIRWireFormat.encodeDataType(.integer, into: &writer)
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            try QueryIRWireFormat.decode(ByteString(Array(tablePrefix) + [0] + Array(columnPrefix) + [255]))
        }
    }

    private func rejectUnknownTag(after prefix: [UInt8]) throws {
        #expect(throws: DatabaseWireError.invalidValueTag(255)) { try QueryIRWireFormat.decode(ByteString(prefix + [255])) }
    }

    @Test("Every nested DDL discriminator rejects unknown bytes before child assembly")
    func nestedUnknownTags() throws {
        let table = Array(try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
        })
        let name = Array(try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try writer.writeString("a")
        })
        let integer = Array(try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeDataType(.integer, into: &writer)
        })
        let countOne: [UInt8] = [1, 0, 0, 0]
        let alter = [13, 4] + table + countOne
        try rejectUnknownTag(after: alter)
        let constraint = alter + [8, 0]
        try rejectUnknownTag(after: constraint)
        try rejectUnknownTag(after: constraint + [0])
        let foreign = constraint + [0, 4] + countOne + name + table + [0]
        try rejectUnknownTag(after: foreign)
        try rejectUnknownTag(after: foreign + [0])
        try rejectUnknownTag(after: foreign + [0, 0])
        let unique = constraint + [0, 1] + countOne + name
        try rejectUnknownTag(after: unique)
        let column = [13, 3] + table + [0] + countOne + name + integer
        try rejectUnknownTag(after: column)
        try rejectUnknownTag(after: column + [2])
        #expect(throws: DatabaseWireError.invalidBool(2)) {
            try QueryIRWireFormat.decode(ByteString(column + [1, 63, 2]))
        }
        #expect(throws: DatabaseWireError.invalidBool(2)) {
            try QueryIRWireFormat.decode(ByteString(constraint + [1, 2]))
        }
        let sequence = [13, 13] + table
        try rejectUnknownTag(after: sequence + [0, 0, 0, 1])
        try rejectUnknownTag(after: sequence + [0, 0, 0, 0, 1])
        try rejectUnknownTag(after: sequence + [0, 0, 0, 0, 0, 0, 1])
        #expect(throws: DatabaseWireError.invalidBool(2)) {
            try QueryIRWireFormat.decode(ByteString(sequence + [0, 0, 0, 0, 0, 1, 2]))
        }
        try rejectUnknownTag(after: [13, 14] + table + [0, 0, 0, 0, 0, 0, 1])
        let key = Array(try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeSortKey(SortKey(.defaultValue), into: &writer)
        })
        try rejectUnknownTag(after: [13, 6] + table + table + countOne + key + [0, 0])
    }

    @Test("Invalid intrinsic DDL is rejected before prepare or any sink emission")
    func invalidShapeHasNoEmission() throws {
        let invalid: [SQLDDLStatement] = [
            .createSchema(name: "", ifNotExists: false), .dropSchema(names: [], ifExists: false, behavior: .restrict),
            .createTable(SQLCreateTable(name: TableRef(table: "t", alias: "alias"), source: .columns([], constraints: []))),
            .alterTable(SQLAlterTable(name: TableRef("t"), actions: [])),
            .createIndex(SQLCreateIndex(name: TableRef("i"), table: TableRef("t"), keys: [])),
            .createView(SQLCreateView(name: TableRef("v"), columns: [], query: query)),
        ]
        for ddl in invalid {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(.ddl(ddl)) }
            var prepared = false
            var emitted = 0
            #expect(throws: DatabaseWireEmissionError<Never>.self) {
                try QueryIRWireFormat.emitCanonicalEncoding(.ddl(ddl),
                    prepare: { _ in prepared = true }, consume: { emitted += $0.count })
            }
            #expect(!prepared); #expect(emitted == 0)
        }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(ByteString([13, 0, 0, 0, 0, 0, 0])) }
    }

    @Test("Deep and wide DDL children use the enclosing frame name count object and nesting budgets")
    func sharedLimits() throws {
        var expression = Expression.parameter(name: "deep_parameter")
        for _ in 0..<100 { expression = .negate(expression) }
        let ddl = SQLDDLStatement.createTable(SQLCreateTable(name: TableRef("table"), source: .columns([
            SQLColumnDefinition(name: "column", type: .integer, policy: .input(defaultExpression: expression)),
        ], constraints: [SQLTableConstraint(kind: .check(expression))])))
        let statement = QueryStatement.ddl(ddl)
        let bytes = try QueryIRWireFormat.encode(statement, limits: limits())
        #expect(try QueryIRWireFormat.decode(bytes, limits: limits()) == statement)
        #expect(try QueryIRWireFormat.encode(statement, limits: limits(frame: bytes.count)) == bytes)
        #expect(try QueryIRWireFormat.decode(bytes, limits: limits(frame: bytes.count)) == statement)
        for restricted in [try limits(frame: bytes.count - 1), try limits(string: 13),
                           try limits(collection: 0), try limits(depth: 100), try limits(objects: 100)] {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(statement, limits: restricted) }
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(bytes, limits: restricted) }
            var emitted = 0
            #expect(throws: DatabaseWireEmissionError<Never>.self) {
                try QueryIRWireFormat.emitCanonicalEncoding(statement, limits: restricted,
                    prepare: { _ in }, consume: { emitted += $0.count })
            }
            #expect(emitted == 0)
        }
        var nested = SelectQuery(projection: [.expression(.parameter(name: "deep"))], source: .values([]))
        for _ in 0..<60 {
            nested = SelectQuery(projection: [.expression(.subquery(nested))], source: .values([]))
        }
        let view = QueryStatement.ddl(.createView(SQLCreateView(name: TableRef("v"), query: nested)))
        let nestedBytes = try QueryIRWireFormat.encode(view, limits: limits())
        #expect(try QueryIRWireFormat.decode(nestedBytes, limits: limits()) == view)
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(nestedBytes, limits: limits(depth: 100)) }
        let columns = (0..<100).map { SQLColumnDefinition(name: "column_\($0)", type: .integer, policy: .input(defaultExpression: .int(Int64($0)))) }
        let wide = QueryStatement.ddl(.createTable(SQLCreateTable(name: TableRef("t"), source: .columns(columns, constraints: []))))
        let wideBytes = try QueryIRWireFormat.encode(wide, limits: limits(collection: 100))
        #expect(try QueryIRWireFormat.decode(wideBytes, limits: limits(collection: 100)) == wide)
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(wide, limits: limits(collection: 99)) }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(wideBytes, limits: limits(collection: 99)) }
    }


    @Test("Column policies constraint kinds and sequence metadata have independent exact bytes")
    func nestedMetadataGoldens() throws {
        let policies: [SQLColumnDefinitionPolicy] = [.input(defaultExpression: .defaultValue),
            .generated(.defaultValue, stored: true), .identity(generation: .byDefault, options: SQLSequenceOptions()), .serial]
        for (tag, policy) in policies.enumerated() {
            let ddl = SQLDDLStatement.createTable(SQLCreateTable(name: TableRef("t"), source: .columns([
                SQLColumnDefinition(name: "a", type: .integer, policy: policy),
            ], constraints: [])))
            let expected = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(13); writer.writeUInt8(3)
                try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                writer.writeUInt8(0); try writer.writeCount(1)
                try writer.writeString("a"); try QueryIRWireFormat.encodeDataType(.integer, into: &writer)
                writer.writeUInt8(UInt8(tag))
                switch tag {
                case 0: writer.writeBool(true); writer.writeUInt8(63)
                case 1: writer.writeUInt8(63); writer.writeBool(true)
                case 2: writer.writeUInt8(1); for _ in 0..<6 { writer.writeBool(false) }
                default: break
                }
                try writer.writeCount(0); try writer.writeCount(0)
                writer.writeBool(false); writer.writeBool(false)
            }
            #expect(try QueryIRWireFormat.encode(.ddl(ddl)) == expected)
        }
        let kinds: [SQLTableConstraintKind] = [.primaryKey(columns: ["a"]), .unique(columns: ["a"], nulls: .notDistinct),
            .notNull(column: "a"), .check(.defaultValue),
            .foreignKey(SQLForeignKeyDefinition(columns: ["a"], referencedTable: TableRef("target"),
                referencedColumns: ["b"], match: .full, onUpdate: .cascade, onDelete: .setDefault, onDeleteColumns: ["a"]))]
        for (tag, kind) in kinds.enumerated() {
            let ddl = SQLDDLStatement.alterTable(SQLAlterTable(name: TableRef("t"), actions: [
                .addConstraint(SQLTableConstraint(name: "c", kind: kind)),
            ]))
            let expected = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(13); writer.writeUInt8(4)
                try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
                try writer.writeCount(1); writer.writeUInt8(8)
                writer.writeBool(true); try writer.writeString("c")
                writer.writeUInt8(0); writer.writeUInt8(UInt8(tag))
                switch tag {
                case 0, 1:
                    try QueryIRWireFormat.writeStrings(["a"], into: &writer)
                    if tag == 1 { writer.writeUInt8(1) }
                case 2: try writer.writeString("a")
                case 3: writer.writeUInt8(63)
                case 4:
                    try QueryIRWireFormat.writeStrings(["a"], into: &writer)
                    try QueryIRWireFormat.encodeTableRef(TableRef("target"), into: &writer)
                    try QueryIRWireFormat.writeOptionalStrings(["b"], into: &writer)
                    writer.writeUInt8(1); writer.writeUInt8(2); writer.writeUInt8(4)
                    try QueryIRWireFormat.writeOptionalStrings(["a"], into: &writer)
                default: throw .invalidQueryIRWireState
                }
                writer.writeBool(false)
            }
            #expect(try QueryIRWireFormat.encode(.ddl(ddl)) == expected)
        }
        let options = SQLSequenceOptions(type: .bigint, start: 7, increment: -2,
            minimum: .value(-10), maximum: SQLSequenceBound.none, cycle: true)
        let ddl = SQLDDLStatement.alterSequence(SQLAlterSequence(name: TableRef("s"), options: options,
            restart: .value(9), ownedBy: .column(table: TableRef("t"), column: "a"), renameTo: "renamed", ifExists: true))
        let expected = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(13); writer.writeUInt8(14)
            try QueryIRWireFormat.encodeTableRef(TableRef("s"), into: &writer)
            writer.writeBool(true); try QueryIRWireFormat.encodeDataType(.bigint, into: &writer)
            writer.writeBool(true); writer.writeInt64(7)
            writer.writeBool(true); writer.writeInt64(-2)
            writer.writeBool(true); writer.writeUInt8(0); writer.writeInt64(-10)
            writer.writeBool(true); writer.writeUInt8(1)
            writer.writeBool(true); writer.writeBool(true)
            writer.writeBool(true); writer.writeUInt8(1); writer.writeInt64(9)
            writer.writeBool(true); writer.writeUInt8(1)
            try QueryIRWireFormat.encodeTableRef(TableRef("t"), into: &writer)
            try writer.writeString("a")
            try QueryIRWireFormat.writeOptionalString("renamed", into: &writer)
            writer.writeBool(true)
        }
        #expect(try QueryIRWireFormat.encode(.ddl(ddl)) == expected)
    }


    @Test("Exact and one-past metadata ledgers reject before absent-width allocation")
    func exactMetadataLimits() throws {
        let schema = QueryStatement.ddl(.createSchema(name: "é", ifNotExists: true))
        let bytes = try QueryIRWireFormat.encode(schema)
        let exact = try limits(frame: bytes.count, string: 2, collection: 0, depth: 2, objects: 2)
        #expect(try QueryIRWireFormat.encode(schema, limits: exact) == bytes)
        #expect(try QueryIRWireFormat.decode(bytes, limits: exact) == schema)
        for restricted in [try limits(frame: bytes.count - 1), try limits(string: 1),
                           try limits(depth: 1), try limits(objects: 1)] {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(schema, limits: restricted) }
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(bytes, limits: restricted) }
        }
        let drop = QueryStatement.ddl(.dropSchema(names: ["a", "b"], ifExists: false, behavior: .restrict))
        let dropBytes = try QueryIRWireFormat.encode(drop)
        #expect(try QueryIRWireFormat.decode(dropBytes, limits: limits(collection: 2, objects: 4)) == drop)
        #expect(throws: DatabaseWireError.collectionTooLarge(actual: 2, maximum: 1)) {
            try QueryIRWireFormat.decode(dropBytes, limits: limits(collection: 1))
        }
        let absentWidth = ByteString([13, 2, 0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decode(absentWidth) }
        let admittedButAbsentWidth = ByteString([13, 2, 0xA0, 0x86, 1, 0])
        #expect(throws: DatabaseWireError.truncated) { try QueryIRWireFormat.decode(admittedButAbsentWidth) }
        #expect(throws: DatabaseWireError.invalidUTF8) {
            try QueryIRWireFormat.decode(ByteString([13, 0, 1, 0, 0, 0, 0xFF, 0]))
        }
    }
}
