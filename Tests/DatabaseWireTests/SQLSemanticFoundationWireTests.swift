import DatabaseTypes
@_spi(DatabaseExecution) @testable import DatabaseWire
import DatabaseKit
import Testing

@Suite("SQL semantic foundation Wire")
struct SQLSemanticFoundationWireTests {
    @Test("Unknown SQL constants retain dedicated tag and exact UTF-8")
    func unknownStringGolden() throws {
        let literal = Literal.sqlUnknownString("é")
        let bytes = try encodeLiteral(literal)
        #expect(bytes == ByteString([19, 2, 0, 0, 0, 0xc3, 0xa9]))
        var reader = DatabaseWireReader(bytes)
        #expect(try QueryIRWireFormat.decodeLiteral(from: &reader) == literal)
        try reader.ensureFullyRead()
        #expect(try encodeLiteral(.string("é"))[0] == 4)
    }

    @Test("Function schema and name remain separate exact identities")
    func qualifiedFunctionRoundTrip() throws {
        for schema: String? in [nil, "", "Exact.Schema"] {
            let expression = Expression.function(FunctionCall(name: "Exact.Function", arguments: [.literal(.sqlUnknownString("x"))], distinct: true, schema: schema))
            let bytes = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try QueryIRWireFormat.encodeExpression(expression, into: &writer)
            }
            #expect(bytes[0] == (schema == nil ? 28 : 43))
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRWireFormat.decodeExpression(from: &reader) == expression)
            try reader.ensureFullyRead()
        }
        let unqualified = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(.function(FunctionCall(name: "f", arguments: [])), into: &writer)
        }
        #expect(unqualified == ByteString([28, 1, 0, 0, 0, 102, 0, 0, 0, 0, 0]))
    }

    @Test("Custom type qualifiers retain dedicated tag and old nil schema bytes")
    func customTypeGolden() throws {
        for schema: String? in [nil, "", "S.s"] {
            let type = DataType.custom("T.t", schema: schema)
            let bytes = try DatabaseWireWriter.encode {
                (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                try QueryIRWireFormat.encodeDataType(type, into: &writer)
            }
            #expect(bytes[0] == (schema == nil ? 21 : 24))
            var reader = DatabaseWireReader(bytes)
            #expect(try QueryIRWireFormat.decodeDataType(from: &reader) == type)
            try reader.ensureFullyRead()
        }
        let bytes = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeDataType(.custom("t"), into: &writer)
        }
        #expect(bytes == ByteString([21, 1, 0, 0, 0, 116]))
    }

    @Test("New grammar rejects every truncated prefix and unknown tags")
    func malformedNewGrammar() throws {
        let literal = try encodeLiteral(.sqlUnknownString("x"))
        for end in 0..<literal.count {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(ByteString(Array(literal[0..<end])))
                _ = try QueryIRWireFormat.decodeLiteral(from: &reader)
            }
        }
        let type = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeDataType(.custom("T", schema: "S"), into: &writer)
        }
        for end in 0..<type.count {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(ByteString(Array(type[0..<end])))
                _ = try QueryIRWireFormat.decodeDataType(from: &reader)
            }
        }
        let expression = try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeExpression(.function(FunctionCall(name: "f", arguments: [.int(1)], schema: "S")), into: &writer)
        }
        for end in 0..<expression.count {
            #expect(throws: DatabaseWireError.self) {
                var reader = DatabaseWireReader(ByteString(Array(expression[0..<end])))
                _ = try QueryIRWireFormat.decodeExpression(from: &reader)
            }
        }
        #expect(throws: DatabaseWireError.invalidValueTag(20)) {
            var reader = DatabaseWireReader([20])
            _ = try QueryIRWireFormat.decodeLiteral(from: &reader)
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            var reader = DatabaseWireReader([255])
            _ = try QueryIRWireFormat.decodeDataType(from: &reader)
        }
        #expect(throws: DatabaseWireError.invalidValueTag(255)) {
            var reader = DatabaseWireReader([255])
            _ = try QueryIRWireFormat.decodeExpression(from: &reader)
        }
    }

    @Test("Qualified productions obey exact and one-past string limits")
    func newStringBudgets() throws {
        let accepted = try DatabaseWireLimits(maximumFrameBytes: 1024, maximumStringBytes: 2,
            maximumByteStringBytes: 1024, maximumCollectionCount: 10, maximumNestingDepth: 64, maximumObjectCount: 100)
        let rejected = try DatabaseWireLimits(maximumFrameBytes: 1024, maximumStringBytes: 1,
            maximumByteStringBytes: 1024, maximumCollectionCount: 10, maximumNestingDepth: 64, maximumObjectCount: 100)
        for limits in [accepted, rejected] {
            let encode = { () throws(DatabaseWireError) -> ByteString in
                try DatabaseWireWriter.encode(limits: limits) {
                    (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
                    try QueryIRWireFormat.encodeExpression(.function(FunctionCall(name: "f", arguments: [.literal(.sqlUnknownString("é"))], schema: "é")), into: &writer)
                }
            }
            if limits.maximumStringBytes == 2 { _ = try encode() }
            else { #expect(throws: DatabaseWireError.self) { try encode() } }
        }
    }

    private func encodeLiteral(_ literal: Literal) throws(DatabaseWireError) -> ByteString {
        try DatabaseWireWriter.encode {
            (writer: inout DatabaseWireWriter) throws(DatabaseWireError) in
            try QueryIRWireFormat.encodeLiteral(literal, into: &writer)
        }
    }
}
