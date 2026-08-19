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
        let articleFields = [
            FieldSchema(name: "title", fieldNumber: 1, type: .string),
            FieldSchema(
                name: "owner",
                fieldNumber: 2,
                type: .reference,
                referenceTargetEntity: "Account"
            ),
            FieldSchema(name: "status", fieldNumber: 3, type: .enum),
        ]
        let articleIndex = try IndexDescriptor(
            entityName: "Article",
            declaration: .ordered(
                name: "Article_title",
                keys: [.ascending(.init(name: "title", number: 1))],
                includedFields: [.init(name: "status", number: 3)],
                unique: true
            ),
            fieldSchemas: articleFields
        )
        let article = try Schema.Entity(
            name: "Article",
            identifierType: .composite([.string, .uint64]),
            fields: articleFields,
            directoryComponents: [
                .staticPath("articles"),
                .dynamicField(fieldName: "status"),
            ],
            directoryLayer: .partition,
            indexes: [articleIndex],
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
                    .ordered(
                        name: "Content_title",
                        keys: [.ascending("title")],
                        includedFields: ["status"]
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
        #"{"formatVersion":2,"formatVersion":2,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[]}"#,
        #"{"formatVersion":2,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[],"unknown":true}"#,
        #"{"formatVersion":2,"schemaVersion":{"major":1,"minor":0,"patch":0}}"#,
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
                #"{"formatVersion":3,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[]}"#
            )
        }
    }

    @Test("Duplicate field identities fail before index construction")
    func duplicateFieldIdentityFails() {
        let json = #"{"formatVersion":2,"schemaVersion":{"major":1,"minor":0,"patch":0},"entities":[{"name":"Entry","identifierType":{"kind":"string"},"fields":[{"name":"value","number":1,"type":"string","optional":false,"array":false,"referenceTargetEntity":null},{"name":"value","number":1,"type":"string","optional":false,"array":false,"referenceTargetEntity":null}],"directory":{"components":[],"layer":"default"},"indexes":[{"entity":"Entry","declaration":{"name":"Entry_value","definition":{"kind":"ordered","keys":[{"field":{"name":"value","number":1},"order":"ascending"}],"includedFields":[],"unique":false}}}],"relationships":[],"fieldAccessRules":[],"enumMetadata":{},"ontology":null,"polymorphicMembership":null}]}"#

        #expect(throws: SchemaJSONError.self) {
            _ = try SchemaJSONCodec().decode(json)
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
    let values: [IndexDefinition<String>] = [
        .ordered(
            keys: [.ascending("title"), .descending("createdAt")],
            includedFields: ["status"],
            unique: true
        ),
        .aggregate(function: .count, groupBy: [.ascending("region")], value: nil),
        .aggregate(function: .sum, groupBy: [.ascending("region")], value: "amount"),
        .aggregate(function: .minimum, groupBy: [], value: "amount"),
        .aggregate(function: .maximum, groupBy: [], value: "amount"),
        .aggregate(function: .average, groupBy: [], value: "amount"),
        .aggregate(function: .nonNullCount, groupBy: [], value: "note"),
        .aggregate(
            function: .approximateDistinct(precision: 10),
            groupBy: [],
            value: "customer"
        ),
        .aggregate(
            function: .percentile(compression: 55.5),
            groupBy: [],
            value: "latency"
        ),
        .updateCount(field: "id"),
        .history(version: "revision", retention: .keepAll),
        .history(version: "revision", retention: .keepLast(3)),
        .history(version: "revision", retention: .keepForDuration(duration)),
        .bitmap(field: "status"),
        .leaderboard(
            groupBy: [.ascending("region")],
            score: "score",
            window: .hourly,
            windowCount: 4
        ),
        .leaderboard(
            groupBy: [],
            score: "score",
            window: .custom(duration: 2.5),
            windowCount: 2
        ),
        .vector(embedding: "embedding", dimensions: 8, metric: .dotProduct),
        .text(
            fields: ["body"],
            mode: .fullText(
                tokenizer: .ngram,
                storePositions: false,
                ngramSize: 2,
                minimumTermLength: 1
            )
        ),
        .text(
            fields: ["title"],
            mode: .autocomplete(
                minimumPrefixLength: 2,
                maximumPrefixLength: 9
            )
        ),
        .spatial(location: "location", encoding: .morton, level: 7),
        .rank(score: "score"),
        .graph(
            .property(
                source: "source",
                label: .implicit,
                target: "target",
                graph: "graph",
                strategy: .adjacency
            ),
            includedFields: ["weight"]
        ),
        .graph(
            .rdf(
                subject: "subject",
                predicate: "predicate",
                object: "object",
                graph: "graph"
            ),
            includedFields: []
        ),
        .graph(
            .ontologyProjection(
                individualIRIBase: "urn:test:",
                graph: try RDFGraphName(iri: "urn:test:graph")
            ),
            includedFields: []
        ),
        .custom(
            CustomIndexDefinition(
                identifier: "example.custom",
                keys: [.ascending("value")],
                includedFields: ["metadata"],
                parameters: ["mode": .string("exact")]
            )
        ),
    ]

    for (index, value) in values.enumerated() {
        let node = try codec.encodeIndexDefinition(
            value,
            encodeField: JSONValue.string
        )
        let decoded: IndexDefinition<String> = try codec.decodeIndexDefinition(
            node,
            path: "definitions[\(index)]",
            decodeField: { value, path in
                guard case .string(let field) = value else {
                    throw SchemaJSONError.invalidValue(
                        path: path,
                        reason: "Expected a field name"
                    )
                }
                return field
            }
        )
        #expect(decoded == value)
    }
}
