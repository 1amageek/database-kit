import DatabaseTypes

extension RDFTerm {
    public static func iri(
        validating value: String
    ) throws(RDFIRIError) -> RDFTerm {
        .iri(try RDFIRI(value))
    }

    public static func blankNode(
        identifier value: String
    ) throws(RDFBlankNodeIdentifierError) -> RDFTerm {
        .blankNode(try RDFBlankNodeIdentifier(value))
    }

    public static func string(_ value: String) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: value,
                datatype: XSDDatatype.string.typedLiteralDatatype
            )
        )
    }

    public static func integer(_ value: Int) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: String(value),
                datatype: XSDDatatype.integer.typedLiteralDatatype
            )
        )
    }

    public static func decimal(_ value: Double) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: String(value),
                datatype: XSDDatatype.decimal.typedLiteralDatatype
            )
        )
    }

    public static func boolean(_ value: Bool) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: value ? "true" : "false",
                datatype: XSDDatatype.boolean.typedLiteralDatatype
            )
        )
    }

    public static func langString(
        _ value: String,
        language: RDFLanguageTag
    ) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: value,
                language: language
            )
        )
    }

    public static func langString(
        _ value: String,
        language: String
    ) throws(RDFLanguageTagError) -> RDFTerm {
        .langString(value, language: try RDFLanguageTag(language))
    }
}
