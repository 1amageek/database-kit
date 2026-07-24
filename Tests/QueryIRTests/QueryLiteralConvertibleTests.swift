import DatabaseTypes
import DatabaseValue
import QueryIR
import Testing

@Suite("Query literal conversion")
struct QueryLiteralConvertibleTests {
    @Test("standard integer conversions preserve signedness and range")
    func integerConversionsPreserveRange() {
        #expect(Int64.min.queryLiteral == .int(Int64.min))
        #expect(UInt64.max.queryLiteral == .uint(UInt64.max))
    }

    @Test("homogeneous arrays convert every element")
    func homogeneousArrayConversion() throws {
        #expect(
            try [UInt16(1), UInt16.max].queryLiteral
                == .array([.uint(1), .uint(UInt64(UInt16.max))])
        )
    }

    @Test("optional nil converts to the canonical null literal")
    func optionalNilConversion() throws {
        let value: Int64? = nil

        #expect(try value.queryLiteral == .null)
    }

    @Test("database arrays retain exact scalar representations")
    func databaseArrayConversion() throws {
        let value = FieldValue.array([
            .int64(Int64.min),
            .uint64(UInt64.max),
            .decimal(ExactDecimal(coefficient: 123, scale: 2)),
        ])

        #expect(
            try value.queryLiteral
                == .array([
                    .int(Int64.min),
                    .uint(UInt64.max),
                    .decimal(coefficient: 123, scale: 2),
                ])
        )
    }

    @Test("database objects fail instead of silently producing a literal")
    func databaseObjectConversionFails() {
        #expect(throws: QueryLiteralConversionError.unsupportedFieldValue) {
            try FieldValue.object(FieldObject()).queryLiteral
        }
    }

    @Test("validated RDF values retain canonical RDF term identity")
    func rdfValueConversion() throws {
        let iri = try RDFIRI("https://example.com/event")

        #expect(
            iri.queryLiteral
                == .rdfTerm(.iri(iri))
        )
    }
}
