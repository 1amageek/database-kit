import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("SQL pattern Wire grammar")
struct SQLPatternWireTests {
    private var kinds: [PatternMatchKind] { [.like, .caseInsensitiveLike, .similarTo, .regularExpression, .caseInsensitiveRegularExpression] }

    @Test("Pattern and concatenation tags have deterministic golden bytes")
    func goldenTags() throws {
        for (index, kind) in kinds.enumerated() {
            #expect(try encode(.patternMatch(subject: .null, pattern: .null, escape: nil, kind: kind))
                == ByteString([50, UInt8(index), 0, 0, 0, 0, 0]))
        }
        #expect(try encode(.patternMatch(subject: .null, pattern: .null, escape: .null, kind: .like))
            == ByteString([50, 0, 1, 0, 0, 0, 0, 0, 0]))
        #expect(try encode(.concatenate(.null, .null)) == ByteString([51, 0, 0, 0, 0]))
    }

    @Test("Dynamic pattern metadata survives expression and operation request carriage")
    func roundTrips() throws {
        for kind in kinds {
            let value = Expression.patternMatch(subject: .parameter(.position(1)),
                pattern: .concatenate(.parameter(.position(2)), .literal(.sqlUnknownString("%"))),
                escape: kind.permitsEscape ? .parameter(.position(3)) : nil, kind: kind)
            #expect(try decode(encode(value)) == value)
            let query = SelectQuery(projection: [ProjectionItem(value)], source: .values([]))
            let statement = QueryStatement.select(query)
            let bytes = try QueryIRWireFormat.encode(statement)
            #expect(try QueryIRWireFormat.decode(bytes) == statement)
            let request = QueryExecuteOperation.Request(input: .statement(statement))
            #if DATABASE_KIT_MULTI_BASE
            let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 50, target: .database, request: request)
            #else
            let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 50, request: request)
            #endif
            #expect(try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame).request == request)
        }
    }

    @Test("Retired tags malformed kind escape Boolean and truncated children fail explicitly")
    func malformedProductions() throws {
        for (bytes, error): (ByteString, DatabaseWireError) in [
            ([21], .invalidValueTag(21)), ([50, 5], .invalidValueTag(5)),
            ([50, 0, 2], .invalidBool(2)), ([50, 3, 1], .invalidQueryIRWireState),
        ] { #expect(throws: error) { try decode(bytes) } }
        #expect(throws: DatabaseWireError.invalidQueryIRWireState) {
            try encode(.patternMatch(subject: .null, pattern: .null, escape: .null, kind: .regularExpression))
        }
        for value in [Expression.patternMatch(subject: .col("s"), pattern: .col("p"), escape: .col("e"), kind: .like), .concatenate(.null, .null)] {
            let bytes = try encode(value)
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) { try decode(ByteString(Array(bytes[0..<end]))) }
            }
            #expect(throws: DatabaseWireError.self) { try decode(ByteString(Array(bytes) + [0])) }
        }
    }

    @Test("Pattern strings and nested expressions retain the common Wire resource bounds")
    func resourceBounds() throws {
        let limits = try DatabaseWireLimits(maximumFrameBytes: 4096, maximumStringBytes: 4,
            maximumByteStringBytes: 1024, maximumCollectionCount: 100, maximumNestingDepth: 4, maximumObjectCount: 100)
        let exact = Expression.patternMatch(subject: .null, pattern: .literal(.sqlUnknownString("1234")), escape: nil, kind: .like)
        #expect(try decode(encode(exact, limits: limits), limits: limits) == exact)
        #expect(throws: DatabaseWireError.self) {
            try encode(.patternMatch(subject: .null, pattern: .literal(.sqlUnknownString("12345")), escape: nil, kind: .like), limits: limits)
        }
        var nested = Expression.null
        for _ in 0..<10 { nested = .concatenate(nested, .null) }
        #expect(throws: DatabaseWireError.self) { try encode(nested, limits: limits) }
    }

    private func encode(_ value: Expression, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(value, into: &writer)
        }
    }
    private func decode(_ bytes: ByteString, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> Expression {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let value = try QueryIRWireFormat.decodeExpression(from: &reader)
        try reader.ensureFullyRead()
        return value
    }
}
