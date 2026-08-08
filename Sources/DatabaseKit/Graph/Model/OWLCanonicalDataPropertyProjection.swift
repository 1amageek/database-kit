import DatabaseTypes

/// Projects canonical persisted values with the same RDF lexical contract used
/// by compiled `OWLDataPropertyValue` conformances.
public enum OWLCanonicalDataPropertyProjection {
    public static func terms(
        from value: FieldValue
    ) throws(OWLProjectionError) -> [RDFTerm] {
        switch value {
        case .null:
            return []
        case .array(let values):
            var projectedTerms: [RDFTerm] = []
            for value in values {
                projectedTerms.append(contentsOf: try terms(from: value))
            }
            return projectedTerms
        case .rdfTerm(let term):
            guard case .literal = term else {
                throw .dataPropertyRequiresLiteral
            }
            return [term]
        case .string(let value):
            return [OWLRDFVocabulary.literal(value, datatype: .string)]
        case .int8(let value):
            return [integer(String(value))]
        case .int16(let value):
            return [integer(String(value))]
        case .int32(let value):
            return [integer(String(value))]
        case .int64(let value):
            return [integer(String(value))]
        case .uint8(let value):
            return [nonNegativeInteger(String(value))]
        case .uint16(let value):
            return [nonNegativeInteger(String(value))]
        case .uint32(let value):
            return [nonNegativeInteger(String(value))]
        case .uint64(let value):
            return [nonNegativeInteger(String(value))]
        case .float32(let value):
            return [
                OWLRDFVocabulary.literal(
                    OWLRDFLexicalForm.floatingPoint(Double(value)),
                    datatype: .float
                )
            ]
        case .float64(let value):
            return [
                OWLRDFVocabulary.literal(
                    OWLRDFLexicalForm.floatingPoint(value),
                    datatype: .double
                )
            ]
        case .bool(let value):
            return [
                OWLRDFVocabulary.literal(
                    value ? "true" : "false",
                    datatype: .boolean
                )
            ]
        case .date(let value):
            return [
                OWLRDFVocabulary.literal(
                    OWLRDFLexicalForm.date(value),
                    datatype: .date
                )
            ]
        case .timestamp(let value):
            let lexicalForm: String
            do {
                lexicalForm = try OWLRDFLexicalForm.dateTime(value)
            } catch let error {
                throw .invalidDateTime(error)
            }
            return [
                OWLRDFVocabulary.literal(
                    lexicalForm,
                    datatype: .dateTime
                )
            ]
        case .uuid(let value):
            return [
                OWLRDFVocabulary.literal(
                    value.description,
                    datatype: .string
                )
            ]
        case .bytes(let value):
            return [
                OWLRDFVocabulary.literal(
                    QueryLiteralEncoding.base64(value),
                    datatype: .base64Binary
                )
            ]
        default:
            throw .unsupportedCanonicalValue(value.owlProjectionSemanticName)
        }
    }

    private static func integer(_ lexicalForm: String) -> RDFTerm {
        OWLRDFVocabulary.literal(lexicalForm, datatype: .integer)
    }

    private static func nonNegativeInteger(_ lexicalForm: String) -> RDFTerm {
        OWLRDFVocabulary.literal(
            lexicalForm,
            datatype: .nonNegativeInteger
        )
    }
}

extension FieldValue {
    var owlProjectionSemanticName: String {
        switch self {
        case .null: return "null"
        case .bool: return "bool"
        case .int8: return "int8"
        case .int16: return "int16"
        case .int32: return "int32"
        case .int64: return "int64"
        case .uint8: return "uint8"
        case .uint16: return "uint16"
        case .uint32: return "uint32"
        case .uint64: return "uint64"
        case .float32: return "float32"
        case .float64: return "float64"
        case .decimal: return "decimal"
        case .string: return "string"
        case .bytes: return "bytes"
        case .date: return "date"
        case .time: return "time"
        case .dateTime: return "dateTime"
        case .timestamp: return "timestamp"
        case .timeSpan: return "timeSpan"
        case .calendarPeriod: return "calendarPeriod"
        case .geographicPoint: return "geographicPoint"
        case .geographicPosition: return "geographicPosition"
        case .vector: return "vector"
        case .uuid: return "uuid"
        case .array: return "array"
        case .object: return "object"
        case .reference: return "reference"
        case .rdfTerm: return "rdfTerm"
        }
    }
}
