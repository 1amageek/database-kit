import DatabaseTypes

public enum OWLRDFVocabulary {
    public static let rdfType = RDFPredicateIRI(
        requiredIRI(
            "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        )
    )

    public static func literal(
        _ lexicalForm: String,
        datatype: XSDDatatype
    ) -> RDFTerm {
        .literal(
            RDFLiteral(
                lexicalForm: lexicalForm,
                datatype: datatype.typedLiteralDatatype
            )
        )
    }

    private static func requiredIRI(_ value: String) -> RDFIRI {
        do {
            return try RDFIRI(value)
        } catch {
            preconditionFailure("Invalid built-in RDF vocabulary IRI: \(value)")
        }
    }
}
