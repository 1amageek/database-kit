import DatabaseKit
import DatabaseTypes
import DatabaseWire
import DatabaseSchemaJSON
import Testing

@Suite("Query column type JSON")
struct QueryColumnTypeJSONCodecTests {

    @Test("Temporal JSON descriptors retain nil, zero, all precisions, and timezone flags")
    func temporalPrecisionRoundTrip() throws {
        let codec = QueryColumnTypeJSONCodec()
        for zone in [false, true] {
            for precision: Int? in [nil, 0, 1, 2, 3, 4, 5, 6] {
                for type: DataType in [.time(withTimeZone: zone, precision: precision),
                                      .timestamp(withTimeZone: zone, precision: precision)] {
                    let descriptor = QueryColumnType.sql(type)
                    #expect(try codec.decode(codec.encode(descriptor)) == descriptor)
                }
            }
        }
        #expect(try codec.encode(.sql(.time(withTimeZone: false, precision: 0))) ==
                #"{"kind":"sql","type":{"kind":"time","withTimeZone":false,"precision":0}}"#)
        for text in [
            #"{"kind":"sql","type":{"kind":"time","withTimeZone":false}}"#,
            #"{"kind":"sql","type":{"kind":"time","withTimeZone":false,"precision":7}}"#,
            #"{"kind":"sql","type":{"kind":"timestamp","withTimeZone":true,"precision":-1}}"#,
            #"{"kind":"sql","type":{"kind":"timestamp","withTimeZone":true,"precision":1.0}}"#,
        ] {
            #expect(throws: SchemaJSONError.self) { try codec.decode(text) }
        }
    }

    @Test("Resolved descriptors preserve exact type parameters and primitive arrays")
    func resolvedTypesRoundTrip() throws {
        let types: [QueryColumnType] = [
            .primitive(.rdfTerm), .primitive(.reference), .primitive(.vector, isArray: true),
            .sql(.boolean), .sql(.smallint), .sql(.integer), .sql(.bigint),
            .sql(.real), .sql(.doublePrecision), .sql(.text), .sql(.date),
            .sql(.interval), .sql(.blob), .sql(.json), .sql(.jsonb), .sql(.uuid),
            .sql(.decimal(precision: nil, scale: nil)), .sql(.decimal(precision: 18, scale: -2)),
            .sql(.char(length: nil)), .sql(.varchar(length: 42)),
            .sql(.binary(length: 1)), .sql(.varbinary(length: nil)),
            .sql(.time(withTimeZone: false)), .sql(.time(withTimeZone: true)),
            .sql(.timestamp(withTimeZone: false)), .sql(.timestamp(withTimeZone: true)),
            .sql(.array(.jsonb)),
        ]
        let codec = QueryColumnTypeJSONCodec()
        for type in types {
            let encoded = try codec.encode(type)
            #expect(try codec.decode(encoded) == type)
            #expect(try codec.encode(codec.decode(encoded)) == encoded)
        }
        #expect(try codec.encode(.sql(.decimal(precision: nil, scale: nil))) ==
                #"{"kind":"sql","type":{"kind":"decimal","precision":null,"scale":null}}"#)
    }

    @Test("Malformed descriptors fail at the exact structural boundary", arguments: [
        #"{"kind":"primitive","type":"string"}"#,
        #"{"kind":"primitive","type":"unknown","isArray":false}"#,
        #"{"kind":"sql","type":{"kind":"text","length":1}}"#,
        #"{"kind":"sql","type":{"kind":"decimal","precision":18}}"#,
        #"{"kind":"sql","type":{"kind":"decimal","precision":1.0,"scale":0}}"#,
        #"{"kind":"sql","type":{"kind":"decimal","precision":999999999999999999999999,"scale":0}}"#,
        #"{"kind":"sql","type":{"kind":"time","withTimeZone":0}}"#,
        #"{"kind":"sql","type":{"kind":"varchar","length":null},"extra":true}"#,
        #"{"kind":"sql","type":{"kind":"array"}}"#,
        #"{"kind":"sql","kind":"primitive","type":{"kind":"text"}}"#,
        #"{"kind":"sql","type":{"kind":"text"}} null"#,
    ])
    func malformedDescriptorsFail(_ text: String) {
        #expect(throws: SchemaJSONError.self) { try QueryColumnTypeJSONCodec().decode(text) }
    }

    @Test("Invalid and unresolved descriptors preserve their admission cause", arguments: [
        #"{"kind":"sql","type":{"kind":"custom","name":"money","schema":null}}"#,
        #"{"kind":"sql","type":{"kind":"array","element":{"kind":"array","element":{"kind":"text"}}}}"#,
        #"{"kind":"sql","type":{"kind":"varchar","length":0}}"#,
        #"{"kind":"sql","type":{"kind":"decimal","precision":0,"scale":0}}"#,
        #"{"kind":"sql","type":{"kind":"decimal","precision":null,"scale":2}}"#,
    ])
    func invalidDescriptorsFail(_ text: String) {
        #expect(throws: SchemaJSONError.invalidQueryValue(path: "queryType", cause: .incompatibleType)) {
            try QueryColumnTypeJSONCodec().decode(text)
        }
    }

    @Test("Descriptor input, output, depth and collection budgets are enforced")
    func descriptorBudgets() throws {
        let type: QueryColumnType = .sql(.array(.integer))
        let codec = QueryColumnTypeJSONCodec()
        let text = try codec.encode(type)
        let bytes = text.utf8.count
        let boundary = try limits(bytes: bytes)
        #expect(try QueryColumnTypeJSONCodec(limits: boundary).decode(text) == type)
        let short = QueryColumnTypeJSONCodec(limits: try limits(bytes: bytes - 1))
        #expect(throws: SchemaJSONError.inputTooLarge(actual: bytes, maximum: bytes - 1)) { try short.decode(text) }
        #expect(throws: SchemaJSONError.outputTooLarge(actual: bytes, maximum: bytes - 1)) { try short.encode(type) }
        let shallow = QueryColumnTypeJSONCodec(limits: try limits(depth: 1))
        #expect(throws: SchemaJSONError.self) { try shallow.decode(text) }
        #expect(throws: SchemaJSONError.self) { try shallow.encode(type) }
        let narrow = QueryColumnTypeJSONCodec(limits: try limits(collections: 1))
        #expect(throws: SchemaJSONError.self) { try narrow.decode(text) }
        #expect(throws: SchemaJSONError.self) { try narrow.encode(type) }
    }

    private func limits(bytes: Int = 4_096, depth: Int = 64, collections: Int = 100) throws -> DatabaseWireLimits {
        try DatabaseWireLimits(maximumFrameBytes: bytes, maximumStringBytes: bytes,
                               maximumByteStringBytes: bytes, maximumCollectionCount: collections,
                               maximumNestingDepth: depth, maximumObjectCount: 100)
    }
}
