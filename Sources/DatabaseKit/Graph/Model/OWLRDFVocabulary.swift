import DatabaseTypes

public enum OWLRDFVocabulary {
    public static var rdfType: RDFPredicateIRI {
        get throws(RDFIRIError) {
            switch rdfTypeResolution {
            case .success(let predicate):
                return predicate
            case .failure(let error):
                throw error
            }
        }
    }

    private static let rdfTypeResolution = resolveRDFType()

    private static func resolveRDFType() -> Result<
        RDFPredicateIRI,
        RDFIRIError
    > {
        do {
            return .success(
                try RDFPredicateIRI(
                    "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
                )
            )
        } catch {
            return .failure(error)
        }
    }

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
}
