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

    public static func subject(
        baseIRI: String,
        persistableType: String,
        identifier: FieldValue
    ) throws(OWLProjectionError) -> RDFSubject {
        .iri(
            try individualIRI(
                baseIRI: baseIRI,
                persistableType: persistableType,
                lexicalForm: try lexicalForm(of: identifier)
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

    public static func terms(
        baseIRI: String,
        persistableType: String,
        value: FieldValue
    ) throws(OWLProjectionError) -> [RDFTerm] {
        switch value {
        case .null:
            return []
        case .array(let values):
            var projectedTerms: [RDFTerm] = []
            for value in values {
                projectedTerms.append(
                    contentsOf: try terms(
                        baseIRI: baseIRI,
                        persistableType: persistableType,
                        value: value
                    )
                )
            }
            return projectedTerms
        case .reference(let reference):
            guard reference.entity == persistableType else {
                throw .objectPropertyTargetMismatch(
                    expected: persistableType,
                    actual: reference.entity
                )
            }
            return [
                .iri(
                    try individualIRI(
                        baseIRI: baseIRI,
                        persistableType: persistableType,
                        lexicalForm: try lexicalForm(of: reference.id)
                    )
                )
            ]
        default:
            throw .unsupportedCanonicalValue(value.owlProjectionSemanticName)
        }
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

    private static func lexicalForm(
        of value: FieldValue
    ) throws(OWLProjectionError) -> String {
        switch value {
        case .bool(let value): return value ? "true" : "false"
        case .int8(let value): return String(value)
        case .int16(let value): return String(value)
        case .int32(let value): return String(value)
        case .int64(let value): return String(value)
        case .uint8(let value): return String(value)
        case .uint16(let value): return String(value)
        case .uint32(let value): return String(value)
        case .uint64(let value): return String(value)
        case .float32(let value):
            return OWLRDFLexicalForm.floatingPoint(Double(value))
        case .float64(let value):
            return OWLRDFLexicalForm.floatingPoint(value)
        case .string(let value): return value
        case .bytes(let value):
            return try lexicalForm(of: ReferenceIdentifier.bytes(value))
        case .uuid(let value): return value.description
        default:
            throw .unsupportedCanonicalValue(value.owlProjectionSemanticName)
        }
    }

    private static func lexicalForm(
        of identifier: ReferenceIdentifier
    ) throws(OWLProjectionError) -> String {
        switch identifier {
        case .bool(let value): return value ? "true" : "false"
        case .int8(let value): return String(value)
        case .int16(let value): return String(value)
        case .int32(let value): return String(value)
        case .int64(let value): return String(value)
        case .uint8(let value): return String(value)
        case .uint16(let value): return String(value)
        case .uint32(let value): return String(value)
        case .uint64(let value): return String(value)
        case .string(let value): return value
        case .bytes(let value):
            let base64 = QueryLiteralEncoding.base64(value)
            var result = ""
            result.reserveCapacity(base64.utf8.count)
            for byte in base64.utf8 {
                switch byte {
                case 43: result.append("-")
                case 47: result.append("_")
                case 61: continue
                default:
                    result.unicodeScalars.append(Unicode.Scalar(byte))
                }
            }
            return result
        case .uuid(let value): return value.description
        case .composite:
            throw .unsupportedIndividualIdentifier
        }
    }
}
