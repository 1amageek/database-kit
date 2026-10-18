import DatabaseKit
import DatabaseTypes
import Testing
@_spi(DatabaseExecution) @testable import DatabaseWire

@Suite("S16 bounded SQL block wire carriage")
struct S16SQLBlockWireTests {
    private var query: SelectQuery {
        SelectQuery(projection: [.expression(.parameter(position: 1), alias: "é")], source: .values([]))
    }
    private func limits(frame: Int = 100_000, string: Int = 1000, bytes: Int = 100_000,
                        collection: Int = 1000, depth: Int = 512, objects: Int = 100_000) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: frame, maximumStringBytes: string,
            maximumByteStringBytes: bytes, maximumCollectionCount: collection,
            maximumNestingDepth: depth, maximumObjectCount: objects)
    }
    private func mixed() throws -> SQLBlock {
        let sequence = try SQLSequence(id: "seq", namespaceID: "public", name: "seq", start: 1,
            increment: 2, minimum: 1, maximum: 100, cycle: true,
            ownedBy: SQLSequenceOwner(relationID: "t", columnID: "id"), declaredType: .integer)
        return try SQLBlock(steps: [.transaction(.begin), .statement(.select(query)),
            .savepoint("é"), .rollbackTo("é"), .release("é"),
            .setConstraints(try .init(selection: .named(["c"]), deferred: true)),
            .sequence(.create(sequence)), .sequence(.alter(sequence, restart: 3)), .sequence(.drop(id: "seq", cascade: false)),
            .setting(.set(name: .searchPath, value: .array([.literal(.string("public"))]), scope: .local)),
            .setting(.show(nil)), .setting(.show(.timeZone)), .setting(.reset(nil, scope: .session)),
            .prepare(.init(name: "p", parameterTypes: [.integer, .array(.text)], statement: .select(query))),
            .execute(.init(name: "p", arguments: [.parameter(position: 1), .array([.int(2)])])), .deallocate("p"), .deallocate(nil),
            .explain(.init(statement: .select(query), options: .init(analyze: true, verbose: true, format: .json))),
            .copy(.init(target: .table(TableRef("t"), columns: ["id"]), direction: .from,
                options: try .init(format: .csv, header: true), data: ByteString([105, 100, 10, 49, 10]))),
            .copy(.init(target: .query(query), direction: .to)), .transaction(.rollback)])
    }

    @Test("Every step and option round trips with deterministic owned and streamed bytes")
    func mixedRoundTrip() throws {
        let block = try mixed()
        let bytes = try QueryIRWireFormat.encode(block)
        #expect(try QueryIRWireFormat.decodeBlock(bytes) == block)
        #expect(try QueryIRWireFormat.encode(block) == bytes)
        var measured = 0
        var streamed: [UInt8] = []
        try QueryIRWireFormat.emitCanonicalEncoding(block, prepare: { measured = $0 }, consume: { streamed.append(contentsOf: $0) })
        #expect(measured == bytes.count); #expect(ByteString(streamed) == bytes)
    }

    @Test("The block envelope is distinct and old ordinary statement tags remain unchanged")
    func additiveTags() throws {
        let statement = QueryStatement.select(query)
        let ordinary = try QueryIRWireFormat.encode(statement)
        #expect(ordinary.first == 0)
        let bytes = try QueryIRWireFormat.encode(SQLBlock(steps: [.statement(statement)]))
        var reader = DatabaseWireReader(bytes)
        #expect(try reader.readUInt8() == 0x42); #expect(try reader.readCount() == 1)
        #expect(try reader.readUInt8() == 0)
        #expect(try QueryIRWireFormat.decodeStatement(from: &reader) == statement)
        try reader.ensureFullyRead()
        #expect(throws: DatabaseWireError.invalidMagic) { try QueryIRWireFormat.decodeBlock(ordinary) }
    }

    @Test("All strict prefixes and trailing bytes fail explicitly")
    func truncatedAndTrailing() throws {
        let bytes = try QueryIRWireFormat.encode(mixed())
        let storage = bytes.withUnsafeBytes { Array($0) }
        for count in 0..<storage.count {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decodeBlock(ByteString(Array(storage.prefix(count)))) }
        }
        #expect(throws: DatabaseWireError.trailingBytes) { try QueryIRWireFormat.decodeBlock(ByteString(storage + [0])) }
    }

    @Test("Unknown step and nested tags plus invalid booleans are rejected")
    func invalidTags() throws {
        for tag: UInt8 in [13, 255] {
            let bytes = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                writer.writeUInt8(0x42); try writer.writeCount(1); writer.writeUInt8(tag)
            }
            #expect(throws: DatabaseWireError.invalidValueTag(tag)) { try QueryIRWireFormat.decodeBlock(bytes) }
        }
        let invalidTransaction = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(0x42); try writer.writeCount(1); writer.writeUInt8(6); writer.writeUInt8(3)
        }
        #expect(throws: DatabaseWireError.invalidValueTag(3)) { try QueryIRWireFormat.decodeBlock(invalidTransaction) }
        let invalidBool = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(0x42); try writer.writeCount(1); writer.writeUInt8(11); writer.writeUInt8(2)
        }
        #expect(throws: DatabaseWireError.invalidBool(2)) { try QueryIRWireFormat.decodeBlock(invalidBool) }
    }

    @Test("Exact frame, name, collection and COPY byte boundaries remain bounded")
    func resourceBoundaries() throws {
        let block = try SQLBlock(steps: [.copy(.init(target: .table(TableRef("t"), columns: []), direction: .from, data: ByteString([1, 2, 3])))])
        let bytes = try QueryIRWireFormat.encode(block)
        let exact = try limits(frame: bytes.count, bytes: 3, collection: 1)
        #expect(try QueryIRWireFormat.encode(block, limits: exact) == bytes)
        #expect(try QueryIRWireFormat.decodeBlock(bytes, limits: exact) == block)
        for restrictive in [try limits(frame: bytes.count - 1), try limits(bytes: 2), try limits(collection: 0), try limits(depth: 1), try limits(objects: 1)] {
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(block, limits: restrictive) }
            #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decodeBlock(bytes, limits: restrictive) }
        }
        let name = try SQLBlock(steps: [.deallocate("é")])
        let encodedName = try QueryIRWireFormat.encode(name, limits: limits(string: 2))
        #expect(try QueryIRWireFormat.decodeBlock(encodedName, limits: limits(string: 2)) == name)
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decodeBlock(encodedName, limits: limits(string: 1)) }
    }

    @Test("Malformed semantic payloads never become successful block values")
    func malformedControls() throws {
        let empty = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(0x42); try writer.writeCount(0)
        }
        #expect(throws: DatabaseWireError.invalidQueryStructure(.emptySQLBlock)) { try QueryIRWireFormat.decodeBlock(empty) }
        let unterminated = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(0x42); try writer.writeCount(1); writer.writeUInt8(6); writer.writeUInt8(0)
        }
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidSQLControl)) { try QueryIRWireFormat.decodeBlock(unterminated) }
        let invalidName = try DatabaseWireWriter.encode { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            writer.writeUInt8(0x42); try writer.writeCount(1); writer.writeUInt8(10); writer.writeBool(true); try writer.writeString("")
        }
        #expect(throws: DatabaseWireError.invalidQueryStructure(.invalidSQLControl)) { try QueryIRWireFormat.decodeBlock(invalidName) }
    }

    @Test("Wire carriage preserves PREPARE definition parameters until explicit invocation")
    func independentPreparation() throws {
        let body = QueryStatement.select(query)
        let block = try SQLBlock(steps: [.prepare(.init(name: "p", parameterTypes: [.integer], statement: body)), .execute(.init(name: "p", arguments: [.int(4)]))])
        let decoded = try QueryIRWireFormat.decodeBlock(QueryIRWireFormat.encode(block))
        let binder = try QueryParameterBinder(parameters: [])
        #expect(try binder.bind(decoded) == block)
    }

    @Test("Deep prepared array types share iterative type codecs and nesting limits")
    func deepTypes() throws {
        var type = DataType.integer
        for _ in 0..<200 { type = .array(type) }
        let block = try SQLBlock(steps: [.prepare(.init(name: "p", parameterTypes: [type], statement: .select(query)))], limits: .init(maximumNestingDepth: 512))
        let generous = try limits(depth: 512)
        let bytes = try QueryIRWireFormat.encode(block, limits: generous)
        #expect(try QueryIRWireFormat.decodeBlock(bytes, limits: generous) == block)
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.encode(block, limits: limits(depth: 200)) }
        #expect(throws: DatabaseWireError.self) { try QueryIRWireFormat.decodeBlock(bytes, limits: limits(depth: 200)) }
    }
}
