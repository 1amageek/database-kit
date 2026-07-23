import DatabaseValue
import QueryIR
import Testing

@Suite("Database literal conversion")
struct DatabaseLiteralConvertibleTests {
    @Test("standard integer conversions preserve signedness and range")
    func integerConversionsPreserveRange() {
        #expect(Int64.min.databaseLiteral == .int(Int64.min))
        #expect(UInt64.max.databaseLiteral == .uint(UInt64.max))
    }

    @Test("homogeneous arrays convert every element")
    func homogeneousArrayConversion() throws {
        #expect(
            try [UInt16(1), UInt16.max].databaseLiteral
                == .array([.uint(1), .uint(UInt64(UInt16.max))])
        )
    }

    @Test("optional nil converts to the canonical null literal")
    func optionalNilConversion() throws {
        let value: Int64? = nil

        #expect(try value.databaseLiteral == .null)
    }

    @Test("database arrays retain exact scalar representations")
    func databaseArrayConversion() throws {
        let value = FieldValue.array([
            .int64(Int64.min),
            .uint64(UInt64.max),
            .decimal(coefficient: 123, scale: 2),
        ])

        #expect(
            try value.databaseLiteral
                == .array([
                    .int(Int64.min),
                    .uint(UInt64.max),
                    .decimal(coefficient: 123, scale: 2),
                ])
        )
    }

    @Test("database objects fail instead of silently producing a literal")
    func databaseObjectConversionFails() {
        #expect(throws: DatabaseLiteralConversionError.unsupportedFieldValue) {
            try FieldValue.object([]).databaseLiteral
        }
    }

    @Test("validated RDF values retain canonical RDF term identity")
    func rdfValueConversion() throws {
        let iri = try DatabaseRDFIRI("https://example.com/event")

        #expect(
            iri.databaseLiteral
                == .rdfTerm(.iri("https://example.com/event"))
        )
    }
}
