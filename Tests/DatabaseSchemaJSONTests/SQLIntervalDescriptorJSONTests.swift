import DatabaseKit
import DatabaseSchemaJSON
import Testing

@Suite("SQL interval descriptor JSON")
struct SQLIntervalDescriptorJSONTests {
    @Test func exactModifierRoundTrips() throws {
        let codec = QueryColumnTypeJSONCodec()
        for fields: SQLIntervalFields? in [nil] + SQLIntervalFields.allCases.map({ Optional($0) }) {
            let type = QueryColumnType.sql(.array(.interval(fields: fields)))
            #expect(try codec.decode(codec.encode(type)) == type)
        }
        let type = QueryColumnType.sql(.interval(fields: .dayToSecond, precision: 3))
        #expect(try codec.encode(type) == #"{"kind":"sql","type":{"kind":"interval","fields":"dayToSecond","precision":3}}"#)
        #expect(try codec.decode(codec.encode(type)) == type)
    }
    @Test func malformedDescriptorsFail() {
        let codec = QueryColumnTypeJSONCodec()
        for text in [
            #"{"kind":"sql","type":{"kind":"interval"}}"#,
            #"{"kind":"sql","type":{"kind":"interval","fields":"bad","precision":null}}"#,
            #"{"kind":"sql","type":{"kind":"interval","fields":"year","precision":3}}"#,
            #"{"kind":"sql","type":{"kind":"interval","fields":null,"precision":7}}"#,
            #"{"kind":"sql","type":{"kind":"interval","fields":null,"precision":1.0}}"#,
            #"{"kind":"sql","type":{"kind":"interval","fields":null,"precision":null,"extra":1}}"#,
        ] { #expect(throws: SchemaJSONError.self) { try codec.decode(text) } }
        #expect(throws: SchemaJSONError.self) { try codec.encode(.sql(.interval(fields: .year, precision: 3))) }
    }
}
