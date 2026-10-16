import DatabaseKit
import DatabaseTypes
import Testing
import Synchronization

private struct CountedQueryField: FieldValueEncodable, FieldValueDecodable {
    static let evaluations = Mutex(0)
    let value: QueryJSONValue

    static var fieldSchemaType: FieldSchemaType { .object }
    static var queryType: QueryColumnType? {
        evaluations.withLock { $0 += 1 }
        return .sql(.json)
    }

    func encodeFieldValue() throws(PersistableEncodingError) -> FieldValue {
        try value.encodeFieldValue()
    }

    static func decodeFieldValue(
        _ value: FieldValue, field: String
    ) throws(PersistableDecodingError) -> Self {
        Self(value: try QueryJSONValue.decodeFieldValue(value, field: field))
    }
}

@Persistable
private struct CountedQueryMetadataModel {
    var id: String
    var value: CountedQueryField?
}

@Persistable
private struct RichQueryArrayModel {
    var id: String
    var values: [QueryNumericValue]
}

@Persistable
private struct OptionalRichQueryArrayModel {
    var id: String
    var values: [QueryNumericValue]?
}

@Persistable
private struct InvalidRichQueryDefaultModel {
    var id: String
    var numeric: QueryNumericValue = try! QueryNumericValue(
        value: ExactDecimal(coefficient: 1, scale: 0),
        displayScale: -1
    )
}

@Persistable
private struct PrimitiveQueryIdentityModel {
    var id: String
    var amount: ExactDecimal
    var bytes: ByteString
    var object: FieldObject
    var values: [Int32]
}

@Suite("Declared rich query model adaptation", .timeLimit(.minutes(1)))
struct RichQueryModelTests {
    private var limits: QueryValueLimits {
        QueryValueLimits(
            maximumRetainedBytes: 16_384,
            maximumTotalNodes: 1_024,
            maximumNestingDepth: 32,
            maximumCollectionElements: 256
        )
    }

    private func model() throws -> RichQueryModel {
        let json = try QueryJSONValue(
            bytes: ByteString(utf8: " {\"b\":1.00, \"a\":null, \"b\":2} "),
            limits: limits
        )
        return RichQueryModel(
            id: "rich",
            numeric: try QueryNumericValue(
                value: ExactDecimal(coefficient: 1, scale: 0),
                displayScale: 2
            ),
            json: json,
            jsonb: try QueryJSONBValue(json: json, limits: limits),
            interval: try QueryIntervalValue(
                period: CalendarPeriod(months: -2, days: 3),
                time: TimeSpan(seconds: -1, nanoseconds: 500_000_000)
            ),
            matrix: try QueryArray<Int32>(
                dimensions: [
                    QueryArrayDimension(lowerBound: -2, length: 2),
                    QueryArrayDimension(lowerBound: 4, length: 2),
                ],
                elements: [1, nil, 3, 4],
                limits: limits
            ),
            optionalJSON: nil
        )
    }

    @Test("S01-C04 numeric scale survives model reload and selected-field update")
    func numericRoundTrip() throws {
        var source = try model()
        let persisted = try PersistedModel(source)
        let decoded = try persisted.decode(as: RichQueryModel.self)
        #expect(decoded.numeric == source.numeric)
        #expect(decoded.numeric.displayScale == 2)
        #expect(try source.persistedFieldValue(for: RichQueryModel.fields.numeric.identity)
            == persisted.value(forFieldNamed: "numeric"))
        source.numeric = try QueryNumericValue(
            value: ExactDecimal(coefficient: 0, scale: 0),
            displayScale: 5
        )
        let updated = try PersistedModel(source).decode(as: RichQueryModel.self)
        #expect(updated.numeric.value == ExactDecimal(coefficient: 0, scale: 0))
        #expect(updated.numeric.displayScale == 5)
        #expect(source.numeric.queryLiteral == .queryValue(
            .numeric(source.numeric), type: .sql(.decimal(precision: nil, scale: nil))
        ))
    }

    @Test("S01-C05 lexical bytes and JSON null differ from outer SQL NULL")
    func lexicalJSONRoundTrip() throws {
        var source = try model()
        let null = try QueryJSONValue(bytes: ByteString(utf8: "null"), limits: limits)
        source.optionalJSON = null
        let decoded = try PersistedModel(source).decode(as: RichQueryModel.self)
        #expect(decoded.json.bytes == source.json.bytes)
        #expect(decoded.optionalJSON == null)
        #expect(try source.persistedFieldValue(for: RichQueryModel.fields.optionalJSON.identity) != .null)
        source.optionalJSON = nil
        let outerNull = try PersistedModel(source)
        #expect(outerNull.value(forFieldNamed: "optionalJSON") == .null)
        #expect(try outerNull.decode(as: RichQueryModel.self).optionalJSON == nil)
    }

    @Test("S01-C06 normalized JSONB survives concrete field reconstruction")
    func jsonbRoundTrip() throws {
        let source = try model()
        let decoded = try PersistedModel(source).decode(as: RichQueryModel.self)
        #expect(decoded.jsonb == source.jsonb)
        #expect(source.jsonb.queryLiteral == .queryValue(.jsonb(source.jsonb), type: .sql(.jsonb)))
    }

    @Test("S01-C07 typed multidimensional arrays preserve bounds and NULL cells")
    func arrayRoundTrip() throws {
        let source = try model()
        let decoded = try PersistedModel(source).decode(as: RichQueryModel.self)
        #expect(decoded.matrix.dimensions == source.matrix.dimensions)
        #expect(decoded.matrix.elements == source.matrix.elements)
        #expect(RichQueryModel.fields.matrix.type == .object)
        #expect(!RichQueryModel.fields.matrix.isArray)
        #expect(RichQueryModel.fields.matrix.queryType == .sql(.array(.integer)))
        #expect(source.matrix.queryLiteral == .queryValue(.array(source.matrix.arrayValue), type: .sql(.array(.integer))))
    }

    @Test("S01-C07 an empty typed SQL array retains its element declaration")
    func emptyArrayRoundTrip() throws {
        let source = try QueryArray<Int32>(dimensions: [], elements: [], limits: limits)
        let payload = try source.encodeFieldValue()
        let decoded = try QueryArray<Int32>.decodeFieldValue(payload, field: "empty")
        #expect(decoded.elements.isEmpty)
        #expect(decoded.dimensions.isEmpty)
        #expect(QueryArray<Int32>.queryType == .sql(.array(.integer)))
    }

    @Test("S01-C08 interval components retain their independent signs")
    func intervalRoundTrip() throws {
        let source = try model()
        let decoded = try PersistedModel(source).decode(as: RichQueryModel.self)
        #expect(decoded.interval == source.interval)
        #expect(decoded.interval.period == CalendarPeriod(months: -2, days: 3))
        #expect(decoded.interval.microseconds == -500_000)
        #expect(source.interval.queryLiteral == .queryValue(.interval(source.interval), type: .sql(.interval())))
    }

    @Test("S01-C09 generated Field and schema use the full declared type metadata")
    func generatedMetadata() throws {
        let schema = try RichQueryModel.schemaEntity
        #expect(schema.fields.first(where: { $0.name == "numeric" })?.queryType == RichQueryModel.fields.numeric.queryType)
        #expect(schema.fields.first(where: { $0.name == "matrix" })?.queryType == RichQueryModel.fields.matrix.queryType)
        let optional = try #require(schema.fields.first(where: { $0.name == "optionalJSON" }))
        #expect(optional.queryType == .sql(.json))
        #expect(optional.isOptional)
        #expect(optional.defaultValue == .null)
        #expect(RichQueryModel.fields.optionalJSON.schema.queryType == optional.queryType)
    }

    @Test("S01-C09 both metadata paths evaluate the declared type accessor once")
    func staticMetadataIsCapturedOnce() throws {
        #expect(CountedQueryMetadataModel.fields.value.queryType == .sql(.json))
        let schema = try CountedQueryMetadataModel.schemaEntity
        #expect(schema.fields.first(where: { $0.name == "value" })?.queryType == .sql(.json))
        #expect(CountedQueryMetadataModel.fields.value.schema.queryType == .sql(.json))
        #expect(CountedQueryField.evaluations.withLock { $0 } == 1)
    }

    @Test("S01-C09 rich defaults use the same envelope and fill only omitted fields")
    func richDefaults() throws {
        let schema = try RichQueryDefaultModel.schemaEntity
        let numeric = try #require(schema.fields.first(where: { $0.name == "numeric" }))
        let defaultValue = try #require(numeric.defaultValue)
        let expected = try QueryNumericValue(value: ExactDecimal(coefficient: 1, scale: 0), displayScale: 2)
        #expect(defaultValue == (try expected.encodeFieldValue()))
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        let decoded = try RichQueryDefaultModel.decodePersistedFields([id])
        #expect(decoded.numeric == expected)
        #expect(decoded.optionalNumeric == nil)
        let outerNull = try PersistableField(number: 2, name: "numeric", value: .null)
        #expect(throws: PersistableDecodingError.self) {
            try RichQueryDefaultModel.decodePersistedFields([id, outerNull])
        }
    }

    @Test("S01-C09 ordinary rich wrapper arrays retain metadata and fail schema admission")
    func ordinaryRichArraysRejected() throws {
        #expect(RichQueryArrayModel.fields.values.queryType == QueryNumericValue.queryType)
        #expect(OptionalRichQueryArrayModel.fields.values.queryType == QueryNumericValue.queryType)
        #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "values", cause: .invalidPersistenceDescriptor)) {
            try RichQueryArrayModel.schemaEntity
        }
        #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "values", cause: .invalidPersistenceDescriptor)) {
            try OptionalRichQueryArrayModel.schemaEntity
        }
    }

    @Test("S01-C09 malformed or mismatched rich defaults preserve typed causes")
    func invalidDefaults() throws {
        #expect(throws: SchemaEntityError.invalidQueryField(
            fieldName: "numeric", cause: .invalidNumericDisplayScale(-1)
        )) {
            try InvalidRichQueryDefaultModel.schemaEntity
        }
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        do {
            _ = try InvalidRichQueryDefaultModel.decodePersistedFields([id])
            Issue.record("An invalid generated default decoded successfully")
        } catch {
            guard case .invalidQueryValue(let field, let cause) = error else {
                Issue.record("The generated default lost its query cause: \(error)")
                return
            }
            #expect(field == "numeric")
            #expect(cause == .invalidNumericDisplayScale(-1))
        }
        let malformed = FieldValue.object(try FieldObject([
            (key: "kind", value: .string("json")),
            (key: "bytes", value: .bytes(ByteString(utf8: "null"))),
            (key: "extra", value: .bool(true)),
        ]))
        do {
            _ = try Schema.Entity(name: "Invalid", identifierType: .string, fields: [FieldSchema(
                name: "value", fieldNumber: 1, type: .object,
                defaultValue: malformed, queryType: .sql(.json)
            )])
            Issue.record("An envelope with an extra key was admitted")
        } catch let error {
            guard case .invalidQueryField(let field, let cause) = error else {
                Issue.record("The query cause was lost: \(error)")
                return
            }
            #expect(field == "value")
            guard case .invalidPersistencePayload = cause else {
                Issue.record("Unexpected intrinsic cause: \(cause)")
                return
            }
        }
        #expect(throws: SchemaEntityError.self) {
            try Schema.Entity(name: "Invalid", identifierType: .string, fields: [FieldSchema(
                name: "value", fieldNumber: 1, type: .string,
                queryType: .sql(.json)
            )])
        }
        #expect(throws: SchemaEntityError.self) {
            try Schema.Entity(name: "Invalid", identifierType: .string, fields: [FieldSchema(
                name: "value", fieldNumber: 1, type: .object,
                defaultValue: .null, queryType: .sql(.json)
            )])
        }
    }

    @Test("S01-C09 malformed model fields preserve query failures during decoding")
    func invalidModelPayload() throws {
        let source = try model()
        var fields = try source.persistedFields()
        let index = try #require(fields.firstIndex(where: { $0.name == "numeric" }))
        fields[index] = try PersistableField(number: fields[index].number, name: "numeric", value: .object(FieldObject()))
        do {
            _ = try RichQueryModel.decodePersistedFields(fields)
            Issue.record("Malformed numeric envelope decoded successfully")
        } catch {
            guard case .invalidQueryValue(let field, let cause) = error else {
                Issue.record("The query cause was lost: \(error)")
                return
            }
            #expect(field == "numeric")
            guard case .invalidPersistencePayload = cause else {
                Issue.record("Unexpected intrinsic cause: \(cause)")
                return
            }
        }
    }

    @Test("S01-C09 descriptor identity changes require explicit migration")
    func descriptorEvolution() throws {
        let previousField = FieldSchema(name: "value", fieldNumber: 1, type: .object, queryType: .sql(.json))
        let currentField = FieldSchema(name: "value", fieldNumber: 1, type: .object, queryType: .sql(.jsonb))
        let previous = try Schema.Entity(name: "Item", identifierType: .string, fields: [previousField])
        let current = try Schema.Entity(name: "Item", identifierType: .string, fields: [currentField])
        #expect(previousField != currentField)
        #expect(Set([previousField, currentField]).count == 2)
        #expect(current.compatibilityReport(from: previous).issues == [
            .changedFieldEncoding(entityName: "Item", fieldName: "value", from: previousField, to: currentField),
        ])
    }

    @Test("S01-C09 rich descriptors are rejected as Directory or primitive index fields")
    func richPlacementRejected() throws {
        let fields = try RichQueryModel.fieldSchemas
        #expect(throws: SchemaEntityError.queryDirectoryField(fieldName: "json")) {
            try Schema.Entity(name: RichQueryModel.persistableType, identifierType: RichQueryModel.persistableIdentifierType, fields: fields, directoryComponents: [.dynamicField(fieldName: "json")])
        }
        let index = try IndexDescriptor(
            entityName: RichQueryModel.persistableType,
            declaration: .ordered(
                name: "rich_included",
                keys: [.ascending(RichQueryModel.fields.id.identity)],
                includedFields: [RichQueryModel.fields.json.identity]
            ),
            fieldSchemas: fields
        )
        #expect(throws: SchemaEntityError.queryIndexField(indexName: "rich_included", fieldName: "json")) {
            try Schema.Entity(name: RichQueryModel.persistableType, identifierType: RichQueryModel.persistableIdentifierType, fields: fields, indexes: [index])
        }
    }

    @Test("S01-C13 primitive field identity and values remain unchanged")
    func primitiveIdentity() throws {
        let envelope = try FieldObject([
            (key: "kind", value: .string("json")),
            (key: "bytes", value: .bytes(ByteString(utf8: "null"))),
        ])
        let source = PrimitiveQueryIdentityModel(
            id: "plain", amount: ExactDecimal(coefficient: 15, scale: 1),
            bytes: ByteString(utf8: "{\"kind\":\"json\"}"), object: envelope, values: [1, 2]
        )
        let stored = try PersistedModel(source)
        #expect(stored.value(forFieldNamed: "amount") == .decimal(source.amount))
        #expect(stored.value(forFieldNamed: "bytes") == .bytes(source.bytes))
        #expect(stored.value(forFieldNamed: "object") == .object(envelope))
        #expect(stored.value(forFieldNamed: "values") == .array([.int32(1), .int32(2)]))
        #expect(try PrimitiveQueryIdentityModel.fieldSchemas.allSatisfy { $0.queryType == nil })
        let decoded = try stored.decode(as: PrimitiveQueryIdentityModel.self)
        #expect(decoded.amount == source.amount)
        #expect(decoded.object == envelope)
        #expect(decoded.values == source.values)
    }
}
