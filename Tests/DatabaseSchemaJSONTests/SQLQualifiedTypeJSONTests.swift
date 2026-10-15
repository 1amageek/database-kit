import DatabaseKit
import DatabaseSchemaJSON
import Testing

@Suite("SQL qualified type JSON")
struct SQLQualifiedTypeJSONTests {
    @Test("Qualified custom types remain explicitly unresolved descriptors")
    func customTypesRemainUnresolved() {
        for schema in ["null", #""Exact.Schema""#] {
            let text = #"{"kind":"sql","type":{"kind":"custom","name":"Exact.Type","schema":\#(schema)}}"#
            #expect(throws: SchemaJSONError.invalidQueryValue(path: "queryType", cause: .incompatibleType)) {
                try QueryColumnTypeJSONCodec().decode(text)
            }
        }
        #expect(throws: SchemaJSONError.invalidQueryValue(path: "queryType", cause: .incompatibleType)) {
            try QueryColumnTypeJSONCodec().encode(.sql(.custom("T", schema: "S")))
        }
    }

    @Test("Custom descriptor schema fields remain strict and mandatory")
    func customSchemaShapeIsStrict() {
        for text in [
            #"{"kind":"sql","type":{"kind":"custom","name":"T"}}"#,
            #"{"kind":"sql","type":{"kind":"custom","name":"T","schema":7}}"#,
            #"{"kind":"sql","type":{"kind":"custom","name":"T","schema":null,"extra":true}}"#,
            #"{"kind":"sql","type":{"kind":"custom","name":"T","schema":null,"schema":"S"}}"#,
        ] {
            #expect(throws: SchemaJSONError.self) { try QueryColumnTypeJSONCodec().decode(text) }
        }
    }
}
