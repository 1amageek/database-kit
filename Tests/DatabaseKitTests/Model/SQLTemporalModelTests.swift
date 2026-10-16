import DatabaseKit
import DatabaseTypes
import Testing

@Persistable
private struct SQLTemporalModelFixture {
    var id: String
    var time: QueryTimeValue = try! QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000)
    var zone: QueryTimeWithTimeZoneValue = QueryTimeWithTimeZoneValue(
        time: try! QueryTimeValue(microsecondsSinceMidnight: 0), utcOffsetSeconds: 57_600)
}

@Persistable
private struct SQLInvalidTemporalDefaultFixture {
    var id: String
    var time: QueryTimeValue = try! QueryTimeValue(microsecondsSinceMidnight: -1)
}

@Suite("SQL temporal model adaptation", .timeLimit(.minutes(1)))
struct SQLTemporalModelTests {
    @Test func staticTimeWrapperAdaptation() throws {
        let source = SQLTemporalModelFixture(id: "time")
        let restored = try SQLTemporalModelFixture.decodePersistedFields(source.persistedFields())
        #expect(restored.time == source.time)
        #expect(restored.zone == source.zone)
        #expect(QueryTimeValue.fieldSchemaType == .time)
        #expect(QueryTimeValue.queryType == .sql(.time(withTimeZone: false)))
        #expect(QueryTimeWithTimeZoneValue.fieldSchemaType == .object)
        #expect(QueryTimeWithTimeZoneValue.queryType == .sql(.time(withTimeZone: true)))
        #expect(source.time.queryLiteral == .queryValue(.time(source.time), type: QueryTimeValue.queryType))
        let limits = QueryValueLimits(maximumRetainedBytes: 4096, maximumTotalNodes: 100,
            maximumNestingDepth: 16, maximumCollectionElements: 100)
        let array = try QueryArray<QueryTimeValue>(dimensions: [QueryArrayDimension(lowerBound: -1, length: 2)],
            elements: [source.time, nil], limits: limits)
        #expect(try QueryArray<QueryTimeValue>.decodeFieldValue(array.encodeFieldValue(), field: "times").elements
            == [source.time, nil])
    }

    @Test func finiteModelRejection() throws {
        let limits = QueryValueLimits(maximumRetainedBytes: 4096, maximumTotalNodes: 100,
            maximumNestingDepth: 16, maximumCollectionElements: 100)
        for sign: QueryTemporalInfinity in [.negative, .positive] {
            let payload = try QueryFieldStorageAdapter.encode(.dateInfinity(sign), type: .sql(.date), limits: limits)
            #expect(throws: PersistableDecodingError.self) { _ = try CivilDate.decodeFieldValue(payload, field: "date") }
            #expect(throws: QueryValueError.incompatibleType) { _ = try CivilDate.decodeQueryValue(.dateInfinity(sign)) }
        }
        let endpoint = try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000)
        #expect(throws: PersistableDecodingError.self) {
            _ = try CivilTime.decodeFieldValue(endpoint.encodeFieldValue(), field: "time")
        }
        let zoned = QueryTimeWithTimeZoneValue(time: endpoint, utcOffsetSeconds: Int32.max)
        #expect(throws: PersistableDecodingError.self) {
            _ = try QueryTimeValue.decodeFieldValue(zoned.encodeFieldValue(), field: "time")
        }
    }

    @Test func temporalStableDefaults() throws {
        let schema = try SQLTemporalModelFixture.schemaEntity
        let time = try #require(schema.fields.first { $0.name == "time" })
        let zone = try #require(schema.fields.first { $0.name == "zone" })
        #expect(time.type == .time)
        #expect(time.queryType == QueryTimeValue.queryType)
        #expect(time.defaultValue == (try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000).encodeFieldValue()))
        #expect(zone.type == .object)
        #expect(zone.queryType == QueryTimeWithTimeZoneValue.queryType)
        let restored = try SQLTemporalModelFixture.decodePersistedFields([
            PersistableField(number: 1, name: "id", value: .string("old"))])
        #expect(restored.time.microsecondsSinceMidnight == 86_400_000_000)
        #expect(restored.zone.utcOffsetSeconds == 57_600)
        #expect(throws: SchemaEntityError.invalidQueryField(fieldName: "time", cause: .timeOutOfRange)) {
            _ = try SQLInvalidTemporalDefaultFixture.schemaEntity
        }
    }
}
