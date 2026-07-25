import DatabaseTypes

public enum OWLIndividualIRIBuilder {
    public static func subject<Identifier: OWLIndividualIdentifier>(
        baseIRI: String,
        persistableType: String,
        identifier: Identifier
    ) throws(OWLProjectionError) -> RDFSubject {
        .iri(
            try individualIRI(
                baseIRI: baseIRI,
                persistableType: persistableType,
                lexicalForm: identifier.owlIndividualIdentifierLexicalForm
            )
        )
    }

    public static func term<Identifier: OWLIndividualIdentifier>(
        baseIRI: String,
        persistableType: String,
        identifier: Identifier
    ) throws(OWLProjectionError) -> RDFTerm {
        .iri(
            try individualIRI(
                baseIRI: baseIRI,
                persistableType: persistableType,
                lexicalForm: identifier.owlIndividualIdentifierLexicalForm
            )
        )
    }

    public static func terms<Value: OWLObjectPropertyValue>(
        baseIRI: String,
        persistableType: String,
        value: Value
    ) throws(OWLProjectionError) -> [RDFTerm] {
        let lexicalForms = value.owlObjectPropertyIdentifierLexicalForms
        var result: [RDFTerm] = []
        result.reserveCapacity(lexicalForms.count)
        for lexicalForm in lexicalForms {
            result.append(
                .iri(
                    try individualIRI(
                        baseIRI: baseIRI,
                        persistableType: persistableType,
                        lexicalForm: lexicalForm
                    )
                )
            )
        }
        return result
    }

    private static func individualIRI(
        baseIRI: String,
        persistableType: String,
        lexicalForm: String
    ) throws(OWLProjectionError) -> RDFIRI {
        do {
            _ = try RDFIRI(baseIRI)
        } catch {
            throw .invalidIndividualIRIBase(baseIRI)
        }
        let separator = baseIRI.hasSuffix("/") || baseIRI.hasSuffix("#") ? "" : "/"
        let value =
            baseIRI
            + separator
            + percentEncode(persistableType)
            + "/"
            + percentEncode(lexicalForm)
        do {
            return try RDFIRI(value)
        } catch {
            throw .invalidIndividualIRI(value)
        }
    }

    private static func percentEncode(_ value: String) -> String {
        let hexadecimal = Array("0123456789ABCDEF".utf8)
        var result: [UInt8] = []
        for byte in value.utf8 {
            let isUnreserved = (65...90).contains(byte)
                || (97...122).contains(byte)
                || (48...57).contains(byte)
                || byte == 45
                || byte == 46
                || byte == 95
                || byte == 126
            if isUnreserved {
                result.append(byte)
            } else {
                result.append(37)
                result.append(hexadecimal[Int(byte >> 4)])
                result.append(hexadecimal[Int(byte & 0x0F)])
            }
        }
        return String(decoding: result, as: UTF8.self)
    }
}
