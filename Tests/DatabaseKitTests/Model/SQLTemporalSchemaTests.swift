import DatabaseKit
import DatabaseTypes
import Testing

@Suite("SQL temporal schema", .timeLimit(.minutes(1)))
struct SQLTemporalSchemaTests {
    private func entity(kind: FieldSchemaType, type: DataType, value: FieldValue?,
                        optional: Bool = false) throws -> Schema.Entity {
        try Schema.Entity(name: "Temporal", identifierType: .string, fields: [
            FieldSchema(name: "value", fieldNumber: 1, type: kind, isOptional: optional,
                        defaultValue: value, queryType: .sql(type))])
    }

    @Test func temporalDefaultsUseDeclaredUnion() throws {
        let limits = QueryValueLimits(maximumRetainedBytes: 4096, maximumTotalNodes: 100,
            maximumNestingDepth: 16, maximumCollectionElements: 100)
        for (kind, type, value): (FieldSchemaType, DataType, QueryValue) in [
            (.date, .date, .dateInfinity(.negative)),
            (.dateTime, .timestamp(withTimeZone: false), .timestampInfinity(.positive, withTimeZone: false)),
            (.timestamp, .timestamp(withTimeZone: true), .timestampInfinity(.negative, withTimeZone: true)),
            (.time, .time(withTimeZone: false), .time(try QueryTimeValue(microsecondsSinceMidnight: 86_400_000_000))),
            (.object, .interval(), .intervalInfinity(.positive)),
        ] {
            let payload = try QueryFieldStorageAdapter.encode(value, type: .sql(type), limits: limits)
            #expect(try entity(kind: kind, type: type, value: payload).fields[0].defaultValue == payload)
        }
        let raw = FieldValue.date(try CivilDate(year: 2024, month: 2, day: 29))
        #expect(try entity(kind: .date, type: .date, value: raw).fields[0].defaultValue == raw)
        #expect(try entity(kind: .date, type: .date, value: .null, optional: true).fields[0].defaultValue == .null)
    }

    @Test func temporalInvalidDefaultsFail() throws {
        #expect(throws: SchemaEntityError.self) { _ = try entity(kind: .date, type: .date, value: .null) }
        #expect(throws: SchemaEntityError.self) { _ = try entity(kind: .object, type: .date, value: nil) }
        #expect(throws: SchemaEntityError.self) { _ = try entity(kind: .time, type: .time(withTimeZone: true), value: nil) }
        let malformed = FieldValue.object(try FieldObject([
            (key: "kind", value: .string("dateInfinity")), (key: "sign", value: .int8(0))]))
        #expect(throws: SchemaEntityError.self) { _ = try entity(kind: .date, type: .date, value: malformed) }
        #expect(throws: SchemaEntityError.self) {
            _ = try Schema.Entity(name: "Raw", identifierType: .string, fields: [
                FieldSchema(name: "value", fieldNumber: 1, type: .date, defaultValue: malformed)])
        }
    }

    @Test func temporalCapabilityAndDeclarationIdentity() throws {
        for (kind, type): (FieldSchemaType, DataType) in [
            (.date, .date), (.time, .time(withTimeZone: false)),
            (.dateTime, .timestamp(withTimeZone: false)), (.timestamp, .timestamp(withTimeZone: true))] {
            let schema = try Schema.Entity(name: "Temporal", identifierType: .string,
                fields: [FieldSchema(name: "value", fieldNumber: 1, type: kind, queryType: .sql(type))],
                directoryComponents: [.dynamicField(fieldName: "value")])
            #expect(schema.fields[0].type == kind)
        }
        #expect(throws: SchemaEntityError.self) {
            _ = try Schema.Entity(name: "Temporal", identifierType: .string,
                fields: [FieldSchema(name: "value", fieldNumber: 1, type: .object,
                                     queryType: .sql(.time(withTimeZone: true)))],
                directoryComponents: [.dynamicField(fieldName: "value")])
        }
        let bare = FieldSchema(name: "value", fieldNumber: 1, type: .object, queryType: .sql(.interval()))
        let modified = FieldSchema(name: "value", fieldNumber: 1, type: .object,
                                   queryType: .sql(.interval(fields: .dayToSecond, precision: 3)))
        #expect(bare != modified)
        #expect(Set([bare, modified, bare]).count == 2)
        _ = try entity(kind: .object, type: .interval(fields: .dayToSecond, precision: 3), value: nil)
    }
}
