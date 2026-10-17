import DatabaseKit
import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import Testing

@Suite("S13 SQL catalog persistence codec")
struct S13SQLCatalogWireTests {
    private func limits(_ count: Int) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: count, maximumStringBytes: 1024,
                               maximumByteStringBytes: 1024, maximumCollectionCount: 100,
                               maximumNestingDepth: 64, maximumObjectCount: 1000)
    }

    @Test("DEFAULT has fixed tag 63 and remains distinct from NULL")
    func defaultGolden() throws {
        let bytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(.defaultValue, into: &writer)
        }
        #expect(bytes == ByteString([63]))
        var reader = DatabaseWireReader(bytes, limits: .default)
        #expect(try QueryIRWireFormat.decodeExpression(from: &reader) == .defaultValue)
        try reader.ensureFullyRead()
        #expect(try QueryIRWireFormat.encodeExpression(.defaultValue) != QueryIRWireFormat.encodeExpression(.null))
    }

    @Test("INSERT identity override uses strict closed tags and round trips")
    func identityOverrideBytes() throws {
        for (overriding, tag): (SQLIdentityOverride?, UInt8) in [(nil, 0), (.systemValue, 1), (.userValue, 2)] {
            let statement = QueryStatement.insert(InsertQuery(target: TableRef("t"), source: .defaultValues, overriding: overriding))
            let bytes = try QueryIRWireFormat.encode(statement)
            #expect(bytes[bytes.count - 1] == tag)
            #expect(try QueryIRWireFormat.decode(bytes) == statement)
            #expect(throws: DatabaseWireError.self) {
                try QueryIRWireFormat.decode(ByteString(Array(bytes[0..<(bytes.count - 1)])))
            }
            var malformed = Array(bytes)
            malformed[malformed.count - 1] = 3
            #expect(throws: DatabaseWireError.invalidValueTag(3)) {
                try QueryIRWireFormat.decode(ByteString(malformed))
            }
        }
    }

    @Test("Catalog expression envelopes retain nested exact names and DEFAULT leaves")
    func expressionRoundTrips() throws {
        let expressions: [Expression] = [
            .defaultValue, .int(42), .add(.col("é"), .int(1)),
            .function(FunctionCall(name: "nextval", arguments: [.literal(.string("public.s"))])),
            .row([.defaultValue, .col("e\u{0301}")]),
        ]
        for expression in expressions {
            let bytes = try QueryIRWireFormat.encodeExpression(expression)
            #expect(try QueryIRWireFormat.decodeExpression(bytes) == expression)
            #expect(try QueryIRWireFormat.encodeExpression(expression) == bytes)
        }
    }

    @Test("Catalog expressions reject every truncation trailing bytes and noncanonical envelope")
    func malformedExpressionEnvelopes() throws {
        let bytes = try QueryIRWireFormat.encodeExpression(.add(.col("column"), .int(7)))
        for end in 0..<bytes.count {
            #expect(throws: DatabaseWireError.self) {
                try QueryIRWireFormat.decodeExpression(ByteString(Array(bytes[0..<end])))
            }
        }
        #expect(throws: DatabaseWireError.self) {
            try QueryIRWireFormat.decodeExpression(ByteString(Array(bytes) + [0]))
        }
        for query in [
            SelectQuery(projection: [.expression(.int(1), alias: "alias")], source: .values([])),
            SelectQuery(projection: [.expression(.int(1))], source: .values([[.int(1)]])),
            SelectQuery(projection: [.expression(.int(1))], source: .values([]), filter: .literal(.bool(true))),
        ] {
            let invalid = try QueryIRWireFormat.encode(.select(query))
            #expect(throws: DatabaseWireError.invalidQueryIRWireState) { try QueryIRWireFormat.decodeExpression(invalid) }
        }
    }

    @Test("Virtual types reuse primitive and SQL codecs and reject malformed or trailing input")
    func columnTypeRoundTrips() throws {
        let types: [QueryColumnType] = [.primitive(.int64), .primitive(.string, isArray: true), .sql(.integer), .sql(.varchar(length: 23))]
        for type in types {
            let bytes = try QueryIRWireFormat.encodeColumnType(type)
            #expect(try QueryIRWireFormat.decodeColumnType(bytes) == type)
            for end in 0..<bytes.count {
                #expect(throws: DatabaseWireError.self) {
                    try QueryIRWireFormat.decodeColumnType(ByteString(Array(bytes[0..<end])))
                }
            }
            #expect(throws: DatabaseWireError.self) {
                try QueryIRWireFormat.decodeColumnType(ByteString(Array(bytes) + [0]))
            }
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            try QueryIRWireFormat.decodeColumnType(ByteString([255]))
        }
    }

    @Test("Expression and column type adapters respect exact and one-past frame budgets")
    func frameBoundaries() throws {
        let expression = Expression.add(.int(7), .int(9))
        let encoded = try QueryIRWireFormat.encodeExpression(expression)
        #expect(try QueryIRWireFormat.encodeExpression(expression, limits: limits(encoded.count)) == encoded)
        #expect(try QueryIRWireFormat.decodeExpression(encoded, limits: limits(encoded.count)) == expression)
        #expect(throws: DatabaseWireError.self) {
            try QueryIRWireFormat.encodeExpression(expression, limits: limits(encoded.count - 1))
        }
        #expect(throws: DatabaseWireError.self) {
            try QueryIRWireFormat.decodeExpression(encoded, limits: limits(encoded.count - 1))
        }
        let type = QueryColumnType.sql(.integer)
        let typeBytes = try QueryIRWireFormat.encodeColumnType(type)
        #expect(try QueryIRWireFormat.encodeColumnType(type, limits: limits(typeBytes.count)) == typeBytes)
        #expect(try QueryIRWireFormat.decodeColumnType(typeBytes, limits: limits(typeBytes.count)) == type)
        #expect(throws: DatabaseWireError.self) {
            try QueryIRWireFormat.encodeColumnType(type, limits: limits(typeBytes.count - 1))
        }
        #expect(throws: DatabaseWireError.self) {
            try QueryIRWireFormat.decodeColumnType(typeBytes, limits: limits(typeBytes.count - 1))
        }
    }
}
