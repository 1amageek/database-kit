import DatabaseValue

public enum OWLRDFVocabulary {
    public static let rdfType = DatabaseRDFTerm.iri(
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    )

    public static func literal(
        _ lexicalForm: String,
        datatype: DatabaseXSDDatatype
    ) -> DatabaseRDFTerm {
        .literal(
            DatabaseRDFLiteral(
                lexicalForm: lexicalForm,
                datatype: datatype.typedLiteralDatatype
            )
        )
    }
}
