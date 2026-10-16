import DatabaseKit
import DatabaseTypes
import Testing

@Persistable
private struct StableIntervalDefaultModel {
    var id: String
    var value: QueryIntervalValue = try! QueryIntervalValue(
        period: CalendarPeriod(months: -2, days: 3),
        time: try! TimeSpan(seconds: -1, nanoseconds: 500_000_000)
    )
    var json: QueryJSONValue = try! QueryJSONValue(
        bytes: ByteString(utf8: " null "),
        limits: QueryValueLimits(
            maximumRetainedBytes: 1_024,
            maximumTotalNodes: 128,
            maximumNestingDepth: 16,
            maximumCollectionElements: 32
        )
    )
    var jsonb: QueryJSONBValue = try! QueryJSONBValue(
        root: .null,
        limits: QueryValueLimits(
            maximumRetainedBytes: 1_024,
            maximumTotalNodes: 128,
            maximumNestingDepth: 16,
            maximumCollectionElements: 32
        )
    )
}

@Persistable
private struct StableArrayDefaultModel {
    var id: String
    var value: QueryArray<Int32> = try! QueryArray<Int32>(
        dimensions: [try! QueryArrayDimension(lowerBound: -1, length: 3)],
        elements: [7, nil, 9],
        limits: QueryValueLimits(
            maximumRetainedBytes: 1_024,
            maximumTotalNodes: 128,
            maximumNestingDepth: 16,
            maximumCollectionElements: 32
        )
    )
}

@Persistable
private struct InvalidTimeSpanDefaultModel {
    var id: String
    var value: QueryIntervalValue = try! QueryIntervalValue(
        period: CalendarPeriod(months: 1, days: 2),
        time: try! TimeSpan(seconds: 0, nanoseconds: 1_000_000_000)
    )
}

@Persistable
private struct InvalidIntervalDefaultModel {
    var id: String
    var value: QueryIntervalValue = try! QueryIntervalValue(
        period: CalendarPeriod(months: 1, days: 2),
        time: try! TimeSpan(seconds: 0, nanoseconds: 1)
    )
}

@Persistable
private struct InvalidArrayDefaultModel {
    var id: String
    var value: QueryArray<Int32> = try! QueryArray<Int32>(
        dimensions: [try! QueryArrayDimension(lowerBound: -1, length: 2)],
        elements: [7],
        limits: QueryValueLimits(
            maximumRetainedBytes: 1_024,
            maximumTotalNodes: 128,
            maximumNestingDepth: 16,
            maximumCollectionElements: 32
        )
    )
}

@Persistable
private struct InvalidDimensionDefaultModel {
    var id: String
    var value: QueryArray<Int32> = try! QueryArray<Int32>(
        dimensions: [try! QueryArrayDimension(lowerBound: 1, length: 0)],
        elements: [],
        limits: QueryValueLimits(
            maximumRetainedBytes: 1_024,
            maximumTotalNodes: 128,
            maximumNestingDepth: 16,
            maximumCollectionElements: 32
        )
    )
}

private func unstableIntervalDefault() -> QueryIntervalValue {
    try! QueryIntervalValue(
        period: CalendarPeriod(months: 1),
        time: TimeSpan(seconds: 0)
    )
}

@Persistable
private struct UncapturedIntervalDefaultModel {
    var id: String
    var value: QueryIntervalValue = unstableIntervalDefault()
}

@Suite("Stable rich query defaults", .timeLimit(.minutes(1)))
struct RichQueryStableDefaultTests {
    @Test("S01-C09 stable interval defaults capture all components and decode omitted fields")
    func stableIntervalDefault() throws {
        let schema = try StableIntervalDefaultModel.schemaEntity
        let field = try #require(schema.fields.first(where: { $0.name == "value" }))
        let expected = try QueryIntervalValue(
            period: CalendarPeriod(months: -2, days: 3),
            time: TimeSpan(seconds: -1, nanoseconds: 500_000_000)
        )
        #expect(field.queryType == .sql(.interval()))
        #expect(field.defaultValue == (try expected.encodeFieldValue()))
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        let decoded = try StableIntervalDefaultModel.decodePersistedFields([id])
        #expect(decoded.value == expected)
        #expect(decoded.value.period == CalendarPeriod(months: -2, days: 3))
        #expect(decoded.value.microseconds == -500_000)
        #expect(decoded.json.bytes == ByteString(utf8: " null "))
        #expect(decoded.jsonb.root == .null)
        #expect(schema.fields.first(where: { $0.name == "json" })?.defaultValue == (try decoded.json.encodeFieldValue()))
        #expect(schema.fields.first(where: { $0.name == "jsonb" })?.defaultValue == (try decoded.jsonb.encodeFieldValue()))
        let uncaptured = try UncapturedIntervalDefaultModel.fieldSchemas
        #expect(uncaptured.first(where: { $0.name == "value" })?.defaultValue == nil)
        #expect(throws: PersistableDecodingError.self) {
            try UncapturedIntervalDefaultModel.decodePersistedFields([id])
        }
    }

    @Test("S01-C09 specialized typed-array defaults retain bounds, NULL elements and type")
    func stableArrayDefault() throws {
        let schema = try StableArrayDefaultModel.schemaEntity
        let field = try #require(schema.fields.first(where: { $0.name == "value" }))
        let source = StableArrayDefaultModel(id: "new")
        #expect(field.queryType == .sql(.array(.integer)))
        #expect(field.defaultValue == (try source.value.encodeFieldValue()))
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        let decoded = try StableArrayDefaultModel.decodePersistedFields([id])
        #expect(decoded.value.elements == [7, nil, 9])
        #expect(decoded.value.dimensions == [try QueryArrayDimension(lowerBound: -1, length: 3)])
        #expect(decoded.value == source.value)
    }

    @Test("S01-C09 nested TimeSpan and interval construction failures retain their exact typed causes")
    func invalidIntervalDefaults() throws {
        let constructionCause = PersistableDefaultConstructionError.timeSpan(.invalidNanoseconds(1_000_000_000))
        #expect(throws: SchemaEntityError.invalidFieldDefaultConstruction(fieldName: "value", cause: constructionCause)) {
            try InvalidTimeSpanDefaultModel.schemaEntity
        }
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        do {
            _ = try InvalidTimeSpanDefaultModel.decodePersistedFields([id])
            Issue.record("An invalid TimeSpan default was decoded")
        } catch {
            guard case .invalidFieldDefaultConstruction(let field, let cause) = error else {
                Issue.record("The TimeSpan construction cause was lost: \(error)")
                return
            }
            #expect(field == "value")
            #expect(cause == constructionCause)
        }
        #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "value", cause: .intervalOutOfRange)) {
            try InvalidIntervalDefaultModel.schemaEntity
        }
        do {
            _ = try InvalidIntervalDefaultModel.decodePersistedFields([id])
            Issue.record("An invalid interval default was decoded")
        } catch {
            guard case .invalidQueryValue(let field, let cause) = error else {
                Issue.record("The interval query cause was lost: \(error)")
                return
            }
            #expect(field == "value")
            #expect(cause == .intervalOutOfRange)
        }
    }

    @Test("S01-C09 array and nested dimension construction failures preserve QueryValueError")
    func invalidArrayDefaults() throws {
        let arrayCause = QueryValueError.elementCountMismatch(expected: 2, actual: 1)
        #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "value", cause: arrayCause)) {
            try InvalidArrayDefaultModel.schemaEntity
        }
        #expect(throws: SchemaEntityError.invalidQueryField(
            fieldName: "value", cause: .invalidDimension(lowerBound: 1, length: 0)
        )) {
            try InvalidDimensionDefaultModel.schemaEntity
        }
        let id = try PersistableField(number: 1, name: "id", value: .string("old"))
        do {
            _ = try InvalidArrayDefaultModel.decodePersistedFields([id])
            Issue.record("An invalid array default was decoded")
        } catch {
            guard case .invalidQueryValue(let field, let cause) = error else {
                Issue.record("The array construction cause was lost: \(error)")
                return
            }
            #expect(field == "value")
            #expect(cause == arrayCause)
        }
    }
}
