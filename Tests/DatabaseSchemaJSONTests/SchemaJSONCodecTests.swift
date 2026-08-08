import DatabaseKit
import DatabaseTypes
import DatabaseWire
import Testing
@testable import DatabaseSchemaJSON

@Suite("Schema JSON codec")
struct SchemaJSONCodecTests {
    @Test("An empty schema preserves its canonical manifest")
    func emptySchemaRoundTrip() throws {
        let schema = try Schema(entities: [], version: .init(1, 2, 3))
        let manifest = SchemaManifest(schema: schema)
        let codec = SchemaJSONCodec()
        let encoded = try codec.encode(manifest)
        let decoded = try codec.decode(encoded)

        #expect(try decoded.canonicalBytes() == manifest.canonicalBytes())
    }

    @Test("Every schema declaration preserves its canonical manifest")
    func completeSchemaRoundTrip() throws {
        let account = try Schema.Entity(
            name: "Account",
            identifierType: .string,
            fields: [
                FieldSchema(name: "name", fieldNumber: 1, type: .string),
            ]
        )
        let article = try Schema.Entity(
            name: "Article",
            identifierType: .composite([.string, .uint64]),
            fields: [
                FieldSchema(name: "title", fieldNumber: 1, type: .string),
                FieldSchema(
                    name: "owner",
                    fieldNumber: 2,
                    type: .reference,
                    referenceTargetEntity: "Account"
                ),
                FieldSchema(name: "status", fieldNumber: 3, type: .enum),
            ],
            directoryComponents: [
                .staticPath("articles"),
                .dynamicField(fieldName: "status"),
            ],
            directoryLayer: .partition,
            indexes: [
                IndexDescriptorMetadata(
                    entityName: "Article",
                    name: "Article_title",
                    kind: IndexKindMetadata(
                        identifier: "scalar",
                        subspaceStructure: .flat,
                        fields: [
                            IndexFieldMetadata(
                                identity: FieldIdentity(name: "title", number: 1)
                            ),
                        ],
                        metadata: [
                            "label": .string("primary"),
                            "weights": .array([.uint8(1), .uint8(2)]),
                        ]
                    ),
                    commonOptions: CommonIndexOptions(
                        unique: true,
                        metadata: ["owner": "catalog"]
                    ),
                    storedFieldNames: ["status"]
                ),
            ],
            relationships: [
                RelationshipDescriptor(
                    ownerTypeName: "Article",
                    propertyName: "owner",
                    propertyFieldNumber: 2,
                    relatedTypeName: "Account",
                    cardinality: .requiredToOne,
                    deleteRule: .deny
                ),
            ],
            fieldAccessRules: [
                FieldAccessRule(
                    field: FieldIdentity(name: "status", number: 3),
                    read: .authenticated,
                    write: .roles(["editor"])
                ),
            ],
            enumMetadata: ["status": ["draft", "published"]],
            ontology: .owlClass(
                iri: "urn:Article",
                properties: [
                    OWLDataPropertyDescriptor(
                        name: "Article_title",
                        fieldName: "title",
                        iri: "urn:title",
                        label: "Title"
                    ),
                ]
            ),
            polymorphicMembership: PolymorphicMembership(
                identifier: "Content",
                directoryComponents: [.staticPath("content")],
                directoryLayer: .default,
                indexes: [
                    PolymorphicIndexDefinition(
                        name: "Content_title",
                        definition: .scalar,
                        fields: [PolymorphicIndexField(name: "title")],
                        commonOptions: CommonIndexOptions(sparse: true),
                        storedFieldNames: ["status"]
                    ),
                ]
            )
        )
        let manifest = SchemaManifest(
            schema: try Schema(
                entities: [article, account],
                version: .init(7, 8, 9)
            )
        )
        let codec = SchemaJSONCodec()
        let encoded = try codec.encode(manifest)
        let decoded = try codec.decode(encoded)

        #expect(try decoded.canonicalBytes() == manifest.canonicalBytes())
        #expect(try decoded.fingerprint() == manifest.fingerprint())
    }

    @Test("Duplicate, unknown, and missing fields fail explicitly", arguments: [
        #"{"formatVersion":1,"formatVersion":1,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[]}"#,
        #"{"formatVersion":1,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[],"unknown":true}"#,
        #"{"formatVersion":1,"schemaVersion":{"major":1,"minor":0,"patch":0}}"#,
    ])
    func malformedDocumentFails(_ json: String) {
        #expect(throws: SchemaJSONError.self) {
            try SchemaJSONCodec().decode(json)
        }
    }

    @Test("Unsupported format versions fail before schema construction")
    func unsupportedVersionFails() {
        #expect(throws: SchemaJSONError.self) {
            try SchemaJSONCodec().decode(
                #"{"formatVersion":2,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[]}"#
            )
        }
    }
}

private struct FieldValueFixture: Sendable {
    let name: String
    let json: String
}

private let fieldValueFixtures: [FieldValueFixture] = [
    .init(name: "null", json: #"{"$type":"null"}"#),
    .init(name: "bool", json: #"{"$type":"bool","value":true}"#),
    .init(name: "int8", json: #"{"$type":"int8","value":"-128"}"#),
    .init(name: "int16", json: #"{"$type":"int16","value":"-32768"}"#),
    .init(name: "int32", json: #"{"$type":"int32","value":"-2147483648"}"#),
    .init(name: "int64", json: #"{"$type":"int64","value":"-9223372036854775808"}"#),
    .init(name: "uint8", json: #"{"$type":"uint8","value":"255"}"#),
    .init(name: "uint16", json: #"{"$type":"uint16","value":"65535"}"#),
    .init(name: "uint32", json: #"{"$type":"uint32","value":"4294967295"}"#),
    .init(name: "uint64", json: #"{"$type":"uint64","value":"18446744073709551615"}"#),
    .init(name: "float32", json: #"{"$type":"float32","bits":"3fc00000"}"#),
    .init(name: "float64", json: #"{"$type":"float64","bits":"4004000000000000"}"#),
    .init(name: "decimal", json: #"{"$type":"decimal","value":"123.45"}"#),
    .init(name: "string", json: #"{"$type":"string","value":"hello"}"#),
    .init(name: "bytes", json: #"{"$type":"bytes","value":"AAEC_w"}"#),
    .init(name: "date", json: #"{"$type":"date","year":"2026","month":"8","day":"8"}"#),
    .init(name: "time", json: #"{"$type":"time","hour":"12","minute":"34","second":"56","nanoseconds":"789"}"#),
    .init(name: "dateTime", json: #"{"$type":"dateTime","date":{"$type":"date","year":"2026","month":"8","day":"8"},"time":{"$type":"time","hour":"12","minute":"34","second":"56","nanoseconds":"789"}}"#),
    .init(name: "timestamp", json: #"{"$type":"timestamp","seconds":"1","nanoseconds":"2"}"#),
    .init(name: "timeSpan", json: #"{"$type":"timeSpan","seconds":"-1","nanoseconds":"2"}"#),
    .init(name: "calendarPeriod", json: #"{"$type":"calendarPeriod","months":"2","days":"3"}"#),
    .init(name: "geographicPoint", json: #"{"$type":"geographicPoint","latitudeBits":"3ff0000000000000","longitudeBits":"4000000000000000"}"#),
    .init(name: "geographicPosition", json: #"{"$type":"geographicPosition","latitudeBits":"3ff0000000000000","longitudeBits":"4000000000000000","heightBits":"4008000000000000"}"#),
    .init(name: "vector", json: #"{"$type":"vector","elementType":"float32","values":["3f800000","40000000"]}"#),
    .init(name: "uuid", json: #"{"$type":"uuid","value":"00000000-0000-0000-0000-000000000001"}"#),
    .init(name: "array", json: #"{"$type":"array","value":[{"$type":"string","value":"x"},{"$type":"uint8","value":"1"}]}"#),
    .init(name: "object", json: #"{"$type":"object","value":{"name":{"$type":"string","value":"Ada"}}}"#),
    .init(name: "reference", json: #"{"$type":"reference","entity":"Person","id":{"kind":"composite","value":[{"kind":"string","value":"tenant"},{"kind":"uint64","value":"7"}]},"partitions":{"$type":"object","value":{"region":{"$type":"string","value":"jp"}}}}"#),
    .init(name: "rdfTerm", json: #"{"$type":"rdfTerm","value":{"kind":"tripleTerm","subject":{"kind":"iri","value":"urn:subject"},"predicate":"urn:predicate","object":{"kind":"literal","lexicalForm":"hello","language":"en","direction":"ltr"}}}"#),
]

@Test("Every FieldValue case remains lossless in schema metadata", arguments: fieldValueFixtures)
private func fieldValueRoundTrip(_ fixture: FieldValueFixture) throws {
    let limits = DatabaseWireLimits.default
    let parser = JSONParser(
        maximumBytes: limits.maximumFrameBytes,
        maximumDepth: limits.maximumNestingDepth,
        maximumCollectionCount: limits.maximumCollectionCount
    )
    let codec = FieldValueJSONCodec(
        maximumBytes: limits.maximumFrameBytes,
        maximumDepth: limits.maximumNestingDepth,
        maximumCollectionCount: limits.maximumCollectionCount
    )
    let first = try codec.decode(try parser.parse(fixture.json), path: "metadata")
    let encoded = JSONWriter.encode(try codec.encode(first))
    let second = try codec.decode(try parser.parse(encoded), path: "metadata")

    #expect(first == second, "Failed case: \(fixture.name)")
    #expect(encoded == fixture.json, "Non-canonical case: \(fixture.name)")
}

@Test("Every polymorphic index definition preserves identity")
private func indexDefinitionRoundTrip() throws {
    let codec = SchemaJSONCodec()
    let duration = try TimeSpan(seconds: 5, nanoseconds: 6)
    let values: [IndexDefinition] = [
        .scalar, .count, .sum, .minimum, .maximum, .average,
        .version(strategy: .keepAll),
        .version(strategy: .keepLast(3)),
        .version(strategy: .keepForDuration(duration)),
        .countUpdates, .countNotNull, .bitmap,
        .timeWindowLeaderboard(window: .hourly, windowCount: 4),
        .timeWindowLeaderboard(window: .custom(duration: 2.5), windowCount: 2),
        .distinct(precision: 10),
        .percentile(compression: 55.5),
        .vector(dimensions: 8, metric: .dotProduct),
        .fullText(tokenizer: .ngram, storePositions: false, ngramSize: 2, minTermLength: 1),
        .autocomplete(minPrefixLength: 2, maxPrefixLength: 9),
        .spatial(encoding: .morton, level: 7),
        .rank,
        .permuted(.identity(size: 3)),
        .permuted(.swapping(0, 2, size: 3)),
        .permuted(.ordering([2, 0, 1])),
        .propertyGraph(strategy: .adjacency, label: .implicit),
        .rdfDataset,
    ]

    for (index, value) in values.enumerated() {
        let node = try codec.encodeIndexDefinition(value)
        let decoded = try codec.decodeIndexDefinition(node, path: "definitions[\(index)]")
        #expect(decoded == value)
    }
}
