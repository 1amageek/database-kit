import DatabaseKit
import DatabaseSchemaJSON
import DatabaseWire
import Testing

@Suite("SQL composite descriptor JSON")
struct SQLCompositeDescriptorJSONTests {
    private let valueLimits = QueryValueLimits(maximumRetainedBytes: 65_536,
        maximumTotalNodes: 1_000, maximumNestingDepth: 64, maximumCollectionElements: 1_000)

    @Test func orderedNestedDescriptorsRoundTrip() throws {
        let codec = QueryColumnTypeJSONCodec()
        let empty = try QueryCompositeType(columns: [], limits: valueLimits)
        let nested = try QueryCompositeType(columns: [
            QueryColumn(number: 1, name: "same", type: .sql(.integer), isNullable: false),
            QueryColumn(number: 2, name: "same", type: .primitive(.string), isNullable: true),
            QueryColumn(number: 3, name: "", type: .sql(.array(.composite(empty))), isNullable: true),
        ], limits: valueLimits)
        for type: QueryColumnType in [.sql(.composite(empty)), .sql(.composite(nested))] {
            let text = try codec.encode(type)
            #expect(try codec.decode(text) == type)
            #expect(try codec.encode(codec.decode(text)) == text)
        }
        #expect(try codec.encode(.sql(.composite(empty))) ==
            #"{"kind":"sql","type":{"kind":"composite","columns":[]}}"#)
        let type = QueryColumnType.sql(.composite(nested))
        let text = try codec.encode(type)
        func bounded(_ bytes: Int, objects: Int = 100) throws -> QueryColumnTypeJSONCodec {
            QueryColumnTypeJSONCodec(limits: try DatabaseWireLimits(
                maximumFrameBytes: bytes, maximumStringBytes: bytes,
                maximumByteStringBytes: bytes, maximumCollectionCount: 100,
                maximumNestingDepth: 64, maximumObjectCount: objects))
        }
        let exact = try bounded(text.utf8.count)
        #expect(try exact.encode(type) == text)
        #expect(try exact.decode(text) == type)
        let short = try bounded(text.utf8.count - 1)
        #expect(throws: SchemaJSONError.outputTooLarge(actual: text.utf8.count, maximum: text.utf8.count - 1)) {
            try short.encode(type)
        }
        #expect(throws: SchemaJSONError.inputTooLarge(actual: text.utf8.count, maximum: text.utf8.count - 1)) {
            try short.decode(text)
        }
        let overflowing = try bounded(Int.max, objects: Int.max)
        #expect(throws: SchemaJSONError.invalidQueryValue(path: "queryType", cause: .arithmeticOverflow)) {
            try overflowing.encode(type)
        }
        #expect(throws: SchemaJSONError.invalidQueryValue(path: "queryType", cause: .arithmeticOverflow)) {
            try overflowing.decode(text)
        }
    }

    @Test func closedColumnGrammarAndOrdinalsFail() {
        let codec = QueryColumnTypeJSONCodec()
        for text in [
            #"{"kind":"sql","type":{"kind":"composite"}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[],"extra":true}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":0,"name":"x","type":{"kind":"sql","type":{"kind":"integer"}},"isNullable":true}]}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":2,"name":"x","type":{"kind":"sql","type":{"kind":"integer"}},"isNullable":true}]}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":1.0,"name":"x","type":{"kind":"sql","type":{"kind":"integer"}},"isNullable":true}]}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":1,"name":"x","type":{"kind":"sql","type":{"kind":"integer"}},"isNullable":0}]}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":1,"name":"x","type":{"kind":"sql","type":{"kind":"custom","name":"T","schema":null}},"isNullable":true}]}}"#,
            #"{"kind":"sql","type":{"kind":"composite","columns":[{"number":1,"name":"x","type":{"kind":"sql","type":{"kind":"integer"}},"isNullable":true,"extra":1}]}}"#,
        ] { #expect(throws: SchemaJSONError.self) { try codec.decode(text) } }
    }

    @Test func nestedDepthBudgetIsCumulative() throws {
        let empty = try QueryCompositeType(columns: [], limits: valueLimits)
        let outer = try QueryCompositeType(columns: [
            QueryColumn(number: 1, name: "nested", type: .sql(.composite(empty)), isNullable: true),
        ], limits: valueLimits)
        let type = QueryColumnType.sql(.composite(outer))
        let text = try QueryColumnTypeJSONCodec().encode(type)
        let limits = try DatabaseWireLimits(maximumFrameBytes: 4_096,
            maximumStringBytes: 4_096, maximumByteStringBytes: 4_096,
            maximumCollectionCount: 100, maximumNestingDepth: 4, maximumObjectCount: 100)
        let shallow = QueryColumnTypeJSONCodec(limits: limits)
        #expect(throws: SchemaJSONError.nestingTooDeep(maximum: 4)) { try shallow.encode(type) }
        #expect(throws: SchemaJSONError.nestingTooDeep(maximum: 4)) { try shallow.decode(text) }
    }

    @Test func outerArrayDescriptorQuotaIsCumulative() throws {
        let empty = try QueryCompositeType(columns: [], limits: valueLimits)
        let type = QueryColumnType.sql(.array(.composite(empty)))
        let text = try QueryColumnTypeJSONCodec().encode(type)
        func codec(objects: Int) throws -> QueryColumnTypeJSONCodec {
            QueryColumnTypeJSONCodec(limits: try DatabaseWireLimits(maximumFrameBytes: 4_096,
                maximumStringBytes: 4_096, maximumByteStringBytes: 4_096,
                maximumCollectionCount: 100, maximumNestingDepth: 64, maximumObjectCount: objects))
        }
        let exact = try codec(objects: 2)
        #expect(try exact.encode(type) == text)
        #expect(try exact.decode(text) == type)
        let short = try codec(objects: 1)
        let failure = SchemaJSONError.invalidQueryValue(path: "queryType",
            cause: .resourceLimit(resource: "nodes", actual: 2, maximum: 1))
        #expect(throws: failure) { try short.encode(type) }
        #expect(throws: failure) { try short.decode(text) }
    }
}
