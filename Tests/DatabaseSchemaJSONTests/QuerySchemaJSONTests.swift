import Foundation
import DatabaseKit
import DatabaseTypes
import DatabaseWire
import DatabaseSchemaJSON
import Testing

@Suite("Query schema JSON")
struct QuerySchemaJSONTests {
    @Test("Rich defaults and explicit primitive descriptors retain canonical identity")
    func richSchemaRoundTrip() throws {
        let limits = QueryValueLimits(maximumRetainedBytes: 65_536, maximumTotalNodes: 1_000,
                                      maximumNestingDepth: 64, maximumCollectionElements: 1_000)
        let json = try QueryJSONValue(bytes: ByteString(utf8: " {\"n\":1.00} "), limits: limits)
        let values: [(QueryColumnType, QueryValue)] = [
            (.sql(.json), .json(json)),
            (.sql(.jsonb), .jsonb(try QueryJSONBValue(json: json, limits: limits))),
            (.sql(.decimal(precision: 18, scale: 2)), .numeric(try QueryNumericValue(
                value: ExactDecimal(coefficient: 12345, scale: 2), displayScale: 2
            ))),
            (.sql(.interval), .interval(try QueryIntervalValue(
                period: CalendarPeriod(months: -1, days: 3), time: TimeSpan(seconds: -2, nanoseconds: 123_000)
            ))),
            (.sql(.array(.integer)), .array(try QueryArrayValue(
                elementType: .integer, dimensions: [QueryArrayDimension(lowerBound: -2, length: 2)],
                elements: [.primitive(.int32(7)), .primitive(.null)], limits: limits
            ))),
        ]
        var fields: [FieldSchema] = []
        for (index, item) in values.enumerated() {
            let payload = try QueryFieldStorageAdapter.encode(
                item.1, type: item.0,
                limits: QueryFieldStorageAdapter.inferredLimits(for: item.1, type: item.0)
            )
            fields.append(.init(name: "value_\(index)", fieldNumber: index + 1, type: .object,
                                defaultValue: payload, queryType: item.0))
        }
        fields.append(.init(name: "tags", fieldNumber: 6, type: .string, isArray: true,
                            queryType: .primitive(.string, isArray: true)))
        fields.append(.init(name: "raw", fieldNumber: 7, type: .string))
        let manifest = try manifest(fields: fields)
        let codec = SchemaJSONCodec()
        let text = try codec.encode(manifest)
        let decoded = try codec.decode(text)
        #expect(try decoded.canonicalBytes() == manifest.canonicalBytes())
        #expect(try decoded.fingerprint() == manifest.fingerprint())
        #expect(text.contains(#""queryType":null"#))
        #expect(text.contains(#""queryType":{"kind":"sql","type":{"kind":"json"}}"#))
        let decodedFields = try #require(decoded.schema.entity(named: "Entry")?.fields)
        for (index, item) in values.enumerated() {
            let payload = try #require(decodedFields[index].defaultValue)
            let type = try #require(decodedFields[index].queryType)
            #expect(try QueryFieldStorageAdapter.decode(
                payload, type: type, limits: QueryFieldStorageAdapter.inferredLimits(for: payload, type: type)
            ) == item.1)
        }
        let wireDecoded = try SchemaManifest(canonicalBytes: decoded.canonicalBytes())
        #expect(wireDecoded.schema == manifest.schema)

    }

    @Test("Missing descriptors fail and descriptor changes alter canonical fingerprints")
    func descriptorsAreRequiredAndSignificant() throws {
        let codec = SchemaJSONCodec()
        let plain = try manifest(fields: [.init(name: "value", fieldNumber: 1, type: .string)])
        let text = try codec.encode(plain)
        #expect(throws: SchemaJSONError.missingField(path: "entities[0].fields[0].queryType")) {
            try codec.decode(text.replacingOccurrences(of: #","queryType":null"#, with: ""))
        }
        let primitive = try codec.decode(text.replacingOccurrences(
            of: #""queryType":null"#,
            with: #""queryType":{"kind":"primitive","type":"string","isArray":false}"#
        ))
        let sql = try codec.decode(text.replacingOccurrences(
            of: #""queryType":null"#,
            with: #""queryType":{"kind":"sql","type":{"kind":"text"}}"#
        ))
        #expect(try plain.fingerprint() != primitive.fingerprint())
        #expect(try primitive.fingerprint() != sql.fingerprint())
    }

    @Test("Schema admission errors retain the query cause and field path")
    func invalidFieldAdmissionIsTyped() throws {
        let codec = SchemaJSONCodec()
        let plain = try manifest(fields: [.init(name: "value", fieldNumber: 1, type: .string)])
        let text = try codec.encode(plain).replacingOccurrences(
            of: #""queryType":null"#,
            with: #""queryType":{"kind":"sql","type":{"kind":"json"}}"#
        )
        #expect(throws: SchemaJSONError.invalidQueryValue(
            path: "entities[0].fields[0].queryType", cause: .invalidPersistenceDescriptor
        )) { try codec.decode(text) }
    }

    private func manifest(fields: [FieldSchema]) throws -> SchemaManifest {
        SchemaManifest(schema: try Schema(entities: [
            Schema.Entity(name: "Entry", identifierType: .string, fields: fields),
        ]))
    }
}
