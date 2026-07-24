// RDF literal conveniences for OWL declarations.
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Literals

import DatabaseTypes

extension RDFLiteral {
    /// Create a string literal
    public static func string(_ value: String) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: value,
            datatype: XSDDatatype.string.typedLiteralDatatype
        )
    }

    /// Create an integer literal
    public static func integer(_ value: Int) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.integer.typedLiteralDatatype
        )
    }

    /// Create a decimal literal
    public static func decimal(_ value: Double) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.decimal.typedLiteralDatatype
        )
    }

    /// Create a float literal
    public static func float(_ value: Float) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.float.typedLiteralDatatype
        )
    }

    /// Create a double literal
    public static func double(_ value: Double) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.double.typedLiteralDatatype
        )
    }

    /// Create a boolean literal
    public static func boolean(_ value: Bool) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: value ? "true" : "false",
            datatype: XSDDatatype.boolean.typedLiteralDatatype
        )
    }

    /// Create a canonical XSD date literal.
    public static func date(_ value: CivilDate) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: XSDDateTimeCodec.format(date: value),
            datatype: XSDDatatype.date.typedLiteralDatatype
        )
    }

    /// Create a canonical UTC XSD dateTime literal.
    public static func dateTime(
        _ value: Timestamp
    ) throws -> RDFLiteral {
        RDFLiteral(
            lexicalForm: try XSDDateTimeCodec.format(timestamp: value),
            datatype: XSDDatatype.dateTime.typedLiteralDatatype
        )
    }

    /// Create a language-tagged string
    public static func langString(
        _ value: String,
        language: RDFLanguageTag
    ) -> RDFLiteral {
        RDFLiteral(
            lexicalForm: value,
            language: language
        )
    }

    public static func langString(
        _ value: String,
        language: String
    ) throws -> RDFLiteral {
        RDFLiteral(
            lexicalForm: value,
            language: try RDFLanguageTag(language)
        )
    }

    /// Create a literal with custom datatype
    public static func typed(
        _ value: String,
        datatype: RDFTypedLiteralDatatype
    ) -> RDFLiteral {
        RDFLiteral(lexicalForm: value, datatype: datatype)
    }

    public static func typed(
        _ value: String,
        datatype: String
    ) throws -> RDFLiteral {
        RDFLiteral(
            lexicalForm: value,
            datatype: try RDFTypedLiteralDatatype(datatype)
        )
    }
}

// MARK: - Value Extraction

extension RDFLiteral {
    /// Try to extract as Int
    public var intValue: Int? {
        Int(lexicalForm)
    }

    /// Try to extract as Double
    public var doubleValue: Double? {
        Double(lexicalForm)
    }

    /// Try to extract as Bool
    public var boolValue: Bool? {
        switch lexicalForm {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    /// Extract an untimezoned XSD date without losing timezone information.
    public var databaseDateValue: CivilDate? {
        guard datatypeIRI == XSDDatatype.date.iri else { return nil }
        return XSDDateTimeCodec.parseDate(lexicalForm)
    }

    /// Extract a timezoned XSD dateTime as an absolute timestamp.
    public var timestampValue: Timestamp? {
        guard datatypeIRI == XSDDatatype.dateTime.iri else { return nil }
        return XSDDateTimeCodec.parseTimestamp(lexicalForm)
    }

    /// String value (always available)
    public var stringValue: String {
        lexicalForm
    }
}

// MARK: - XSD Datatypes

// MARK: - XSD Facets

/// XSD facet types for datatype restrictions
public enum XSDFacet: String, Sendable, CaseIterable {
    case minInclusive = "xsd:minInclusive"
    case maxInclusive = "xsd:maxInclusive"
    case minExclusive = "xsd:minExclusive"
    case maxExclusive = "xsd:maxExclusive"
    case length = "xsd:length"
    case minLength = "xsd:minLength"
    case maxLength = "xsd:maxLength"
    case pattern = "xsd:pattern"
    case totalDigits = "xsd:totalDigits"
    case fractionDigits = "xsd:fractionDigits"
    case whiteSpace = "xsd:whiteSpace"
    case langRange = "rdf:langRange"
}

/// Facet restriction for datatype definitions
public struct FacetRestriction: Sendable, Hashable {
    public let facet: XSDFacet
    public let value: RDFLiteral

    public init(facet: XSDFacet, value: RDFLiteral) {
        self.facet = facet
        self.value = value
    }

    // Convenience constructors
    public static func minInclusive(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .minInclusive, value: .integer(value))
    }

    public static func maxInclusive(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .maxInclusive, value: .integer(value))
    }

    public static func minExclusive(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .minExclusive, value: .integer(value))
    }

    public static func maxExclusive(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .maxExclusive, value: .integer(value))
    }

    public static func minLength(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .minLength, value: .integer(value))
    }

    public static func maxLength(_ value: Int) -> FacetRestriction {
        FacetRestriction(facet: .maxLength, value: .integer(value))
    }

    public static func pattern(_ regex: String) -> FacetRestriction {
        FacetRestriction(facet: .pattern, value: .string(regex))
    }

    public static func languageRange(_ range: String) -> FacetRestriction {
        FacetRestriction(facet: .langRange, value: .string(range))
    }
}
