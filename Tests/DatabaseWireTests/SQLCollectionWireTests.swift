import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("SQL collection and variadic Wire grammar")
struct SQLCollectionWireTests {
    @Test("Tags53/54 and every slice-presence combination have exact metadata-first goldens")
    func goldenTags() throws {
        #expect(try encode(.arrayAccess(.null, subscripts: [.index(.null)])) == ByteString([53, 1, 0, 0, 0, 0, 0, 0, 0, 0]))
        for hasLower in [false, true] {
            for hasUpper in [false, true] {
                let expression = Expression.arrayAccess(.null, subscripts: [.slice(lower: hasLower ? .null : nil, upper: hasUpper ? .null : nil)])
                let expected: [UInt8] = [53, 1, 0, 0, 0, 1, hasLower ? 1 : 0, hasUpper ? 1 : 0]
                    + Array(repeating: UInt8(0), count: 2 * (1 + (hasLower ? 1 : 0) + (hasUpper ? 1 : 0)))
                #expect(try encode(expression) == ByteString(expected))
                #expect(try decode(ByteString(expected)) == expression)
            }
        }
        for byte in UInt8(0)...10 {
            let operation = try #require(CollectionOperator(rawValue: byte))
            #expect(try encode(.collectionOperation(operation, left: .null, right: .null)) == ByteString([54, byte, 0, 0, 0, 0]))
        }
        #expect(try encode(.function(FunctionCall(name: "f", arguments: [.null]))) == ByteString([28, 1, 0, 0, 0, 102, 1, 0, 0, 0, 0, 0, 0]))
        #expect(try encode(.function(FunctionCall(name: "f", arguments: [.null], finalArrayIsVariadic: true)))
            == ByteString([55, 0, 1, 0, 0, 0, 102, 1, 0, 0, 0, 0, 0, 0]))
    }

    @Test("Nested groups all operators and qualified variadic metadata survive real operation frames")
    func requestRoundTrips() throws {
        for byte in UInt8(0)...10 {
            let operation = try #require(CollectionOperator(rawValue: byte))
            let grouped = Expression.arrayAccess(.arrayAccess(.parameter(.position(1)), subscripts: [.index(.int(1))]),
                subscripts: [.slice(lower: nil, upper: .parameter(.position(2)))])
            let value = Expression.function(FunctionCall(name: "f", arguments: [
                .collectionOperation(operation, left: grouped, right: .null),
            ], distinct: true, schema: "qualified", finalArrayIsVariadic: true))
            #expect(try decode(encode(value)) == value)
            let statement = QueryStatement.select(SelectQuery(projection: [ProjectionItem(value)], source: .values([])))
            #expect(try QueryIRWireFormat.decode(QueryIRWireFormat.encode(statement)) == statement)
            let request = QueryExecuteOperation.Request(input: .ir(statement))
            #if DATABASE_KIT_MULTI_BASE
            let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 53, target: .database, request: request)
            #else
            let frame = try DatabaseWireEncoder().encodeRequest(DatabaseOperationCatalog.queryExecute, requestID: 53, request: request)
            #endif
            #expect(try DatabaseWireDecoder().decodeRequest(DatabaseOperationCatalog.queryExecute, from: frame).request == request)
        }
    }

    @Test("Closed count metadata operators Booleans and every truncated production fail typed")
    func malformedProductions() throws {
        for (bytes, error): (ByteString, DatabaseWireError) in [
            ([53, 0, 0, 0, 0], .invalidQueryIRWireState),
            ([53, 7, 0, 0, 0], .invalidQueryIRWireState),
            ([53, 1, 0, 0, 0, 2], .invalidValueTag(2)),
            ([53, 1, 0, 0, 0, 1, 2], .invalidBool(2)),
            ([53, 1, 0, 0, 0, 1, 0, 2], .invalidBool(2)),
            ([54, 11], .invalidValueTag(11)), ([55, 2], .invalidBool(2)),
            ([55, 0, 0, 0, 0, 0, 0, 0, 0, 0], .invalidQueryIRWireState),
            ([55, 0, 0, 0, 0, 0, 1, 0, 0, 0, 2], .invalidBool(2)),
        ] { #expect(throws: error) { try decode(bytes) } }
        let values: [Expression] = [
            .arrayAccess(.col("a"), subscripts: [.index(.int(1)), .slice(lower: .null, upper: nil)]),
            .collectionOperation(.jsonDeletePath, left: .null, right: .null),
            .function(FunctionCall(name: "f", arguments: [.null], schema: "s", finalArrayIsVariadic: true)),
        ]
        for value in values {
            let bytes = try encode(value)
            for end in 0..<bytes.count { #expect(throws: DatabaseWireError.self) { try decode(bytes[0..<end]) } }
            #expect(throws: DatabaseWireError.self) { try decode(ByteString(Array(bytes) + [0])) }
        }
        for value: Expression in [.arrayAccess(.null, subscripts: []),
                                   .function(FunctionCall(name: "f", arguments: [], finalArrayIsVariadic: true))] {
            #expect(throws: DatabaseWireError.self) { try encode(value) }
        }
    }

    @Test("Collection count string frame depth and object limits enforce exact and one-past")
    func resourceBounds() throws {
        let value = Expression.arrayAccess(.null, subscripts: [.slice(lower: .null, upper: .null)])
        let bytes = try encode(value)
        let exact = try DatabaseWireLimits(maximumFrameBytes: bytes.count, maximumStringBytes: 100,
            maximumByteStringBytes: 100, maximumCollectionCount: 1, maximumNestingDepth: 3, maximumObjectCount: 8)
        #expect(try decode(encode(value, limits: exact), limits: exact) == value)
        let short = try DatabaseWireLimits(maximumFrameBytes: bytes.count - 1, maximumStringBytes: 100,
            maximumByteStringBytes: 100, maximumCollectionCount: 1, maximumNestingDepth: 3, maximumObjectCount: 8)
        #expect(throws: DatabaseWireError.self) { try encode(value, limits: short) }
        #expect(throws: DatabaseWireError.self) { try decode(bytes, limits: short) }
        let shallow = try DatabaseWireLimits(maximumFrameBytes: 1000, maximumStringBytes: 100,
            maximumByteStringBytes: 100, maximumCollectionCount: 1, maximumNestingDepth: 2, maximumObjectCount: 100)
        #expect(throws: DatabaseWireError.self) { try encode(value, limits: shallow) }
        #expect(throws: DatabaseWireError.self) { try decode(bytes, limits: shallow) }
        let fewerObjects = try DatabaseWireLimits(maximumFrameBytes: 1000, maximumStringBytes: 100,
            maximumByteStringBytes: 100, maximumCollectionCount: 1, maximumNestingDepth: 3, maximumObjectCount: 7)
        #expect(throws: DatabaseWireError.self) { try encode(value, limits: fewerObjects) }
        #expect(throws: DatabaseWireError.self) { try decode(bytes, limits: fewerObjects) }
        let fewerCells = try DatabaseWireLimits(maximumFrameBytes: 1000, maximumStringBytes: 100,
            maximumByteStringBytes: 100, maximumCollectionCount: 0, maximumNestingDepth: 3, maximumObjectCount: 100)
        #expect(throws: DatabaseWireError.self) { try encode(value, limits: fewerCells) }
        #expect(throws: DatabaseWireError.self) { try decode(bytes, limits: fewerCells) }
        let tiny = try DatabaseWireLimits(maximumFrameBytes: 1000, maximumStringBytes: 1,
            maximumByteStringBytes: 100, maximumCollectionCount: 1, maximumNestingDepth: 4, maximumObjectCount: 100)
        #expect(throws: DatabaseWireError.self) {
            try encode(.function(FunctionCall(name: "ff", arguments: [.null], finalArrayIsVariadic: true)), limits: tiny)
        }
    }

    private func encode(_ value: Expression, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode(limits: limits) { (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(value, into: &writer)
        }
    }
    private func decode(_ bytes: ByteString, limits: DatabaseWireLimits = .default) throws(DatabaseWireError) -> Expression {
        var reader = DatabaseWireReader(bytes, limits: limits)
        let expression = try QueryIRWireFormat.decodeExpression(from: &reader)
        try reader.ensureFullyRead()
        return expression
    }
}
