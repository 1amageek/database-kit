// OWLLiteral.swift
// Graph - OWL DL literal values
//
// Provides typed literal values for OWL data properties.
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Literals

import DatabaseValue

/// The canonical RDF literal used by OWL declarations and RDF datasets.
public typealias OWLLiteral = DatabaseRDFLiteral
public typealias XSDDatatype = DatabaseXSDDatatype

extension DatabaseRDFLiteral {
    /// Create a string literal
    public static func string(_ value: String) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: value,
            datatype: XSDDatatype.string.typedLiteralDatatype
        )
    }

    /// Create an integer literal
    public static func integer(_ value: Int) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.integer.typedLiteralDatatype
        )
    }

    /// Create a decimal literal
    public static func decimal(_ value: Double) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.decimal.typedLiteralDatatype
        )
    }

    /// Create a float literal
    public static func float(_ value: Float) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.float.typedLiteralDatatype
        )
    }

    /// Create a double literal
    public static func double(_ value: Double) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: String(value),
            datatype: XSDDatatype.double.typedLiteralDatatype
        )
    }

    /// Create a boolean literal
    public static func boolean(_ value: Bool) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: value ? "true" : "false",
            datatype: XSDDatatype.boolean.typedLiteralDatatype
        )
    }

    /// Create a canonical XSD date literal.
    public static func date(_ value: DatabaseDate) throws -> OWLLiteral {
        OWLLiteral(
            lexicalForm: try DatabaseXSDDateTimeCodec.format(date: value),
            datatype: XSDDatatype.date.typedLiteralDatatype
        )
    }

    /// Create a canonical UTC XSD dateTime literal.
    public static func dateTime(
        _ value: DatabaseTimestamp
    ) throws -> OWLLiteral {
        OWLLiteral(
            lexicalForm: try DatabaseXSDDateTimeCodec.format(timestamp: value),
            datatype: XSDDatatype.dateTime.typedLiteralDatatype
        )
    }

    /// Create a language-tagged string
    public static func langString(
        _ value: String,
        language: DatabaseRDFLanguageTag
    ) -> OWLLiteral {
        OWLLiteral(
            lexicalForm: value,
            language: language
        )
    }

    public static func langString(
        _ value: String,
        language: String
    ) throws -> OWLLiteral {
        OWLLiteral(
            lexicalForm: value,
            language: try DatabaseRDFLanguageTag(language)
        )
    }

    /// Create a literal with custom datatype
    public static func typed(
        _ value: String,
        datatype: DatabaseRDFTypedLiteralDatatype
    ) -> OWLLiteral {
        OWLLiteral(lexicalForm: value, datatype: datatype)
    }

    public static func typed(
        _ value: String,
        datatype: String
    ) throws -> OWLLiteral {
        OWLLiteral(
            lexicalForm: value,
            datatype: try DatabaseRDFTypedLiteralDatatype(datatype)
        )
    }
}

// MARK: - Value Extraction

extension OWLLiteral {
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
    public var databaseDateValue: DatabaseDate? {
        guard datatype == XSDDatatype.date.iri else { return nil }
        return DatabaseXSDDateTimeCodec.parseDate(lexicalForm)
    }

    /// Extract a timezoned XSD dateTime as an absolute timestamp.
    public var timestampValue: DatabaseTimestamp? {
        guard datatype == XSDDatatype.dateTime.iri else { return nil }
        return DatabaseXSDDateTimeCodec.parseTimestamp(lexicalForm)
    }

    /// String value (always available)
    public var stringValue: String {
        lexicalForm
    }
}

// MARK: - XSD Datatypes

// MARK: - XSD Facets

/// XSD facet types for datatype restrictions
public enum XSDFacet: String, Sendable, Codable, CaseIterable {
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
public struct FacetRestriction: Sendable, Codable, Hashable {
    public let facet: XSDFacet
    public let value: OWLLiteral

    public init(facet: XSDFacet, value: OWLLiteral) {
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
