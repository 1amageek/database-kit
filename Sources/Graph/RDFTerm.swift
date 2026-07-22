public import DatabaseValue

/// The canonical RDF term used by graph, query, storage, and wire layers.
public typealias RDFTerm = DatabaseRDFTerm

extension DatabaseRDFTerm {
    public static func string(_ value: String) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: value,
                datatype: DatabaseXSDDatatype.string.typedLiteralDatatype
            )
        )
    }

    public static func integer(_ value: Int) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: String(value),
                datatype: DatabaseXSDDatatype.integer.typedLiteralDatatype
            )
        )
    }

    public static func decimal(_ value: Double) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: String(value),
                datatype: DatabaseXSDDatatype.decimal.typedLiteralDatatype
            )
        )
    }

    public static func boolean(_ value: Bool) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: value ? "true" : "false",
                datatype: DatabaseXSDDatatype.boolean.typedLiteralDatatype
            )
        )
    }

    public static func langString(
        _ value: String,
        language: DatabaseRDFLanguageTag
    ) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: value,
                language: language
            )
        )
    }

    public static func langString(
        _ value: String,
        language: String
    ) throws -> DatabaseRDFTerm {
        .langString(value, language: try DatabaseRDFLanguageTag(language))
    }
}
