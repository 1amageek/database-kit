// OWLLiteral.swift
// Graph - OWL DL literal values
//
// Provides typed literal values for OWL data properties.
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Literals

import Foundation

/// OWL Literal value
///
/// Represents a typed data value in OWL ontologies.
/// Supports XSD datatypes and language-tagged strings.
///
/// **Example**:
/// ```swift
/// let name = OWLLiteral.string("Alice")
/// let age = OWLLiteral.integer(30)
/// let label = OWLLiteral.langString("Hello", language: "en")
/// ```
public struct OWLLiteral: Sendable, Codable, Hashable {
    /// Lexical form (string representation of the value)
    public let lexicalForm: String

    /// Datatype IRI (e.g., "xsd:string", "xsd:integer")
    public let datatype: String

    /// Language tag (for rdf:langString)
    public let language: String?

    // MARK: - Initialization

    public init(lexicalForm: String, datatype: String, language: String? = nil) {
        self.lexicalForm = lexicalForm
        self.datatype = datatype
        self.language = language
    }

    // MARK: - Convenience Constructors

    /// Create a string literal
    public static func string(_ value: String) -> OWLLiteral {
        OWLLiteral(lexicalForm: value, datatype: XSDDatatype.string.iri)
    }

    /// Create an integer literal
    public static func integer(_ value: Int) -> OWLLiteral {
        OWLLiteral(lexicalForm: String(value), datatype: XSDDatatype.integer.iri)
    }

    /// Create a decimal literal
    public static func decimal(_ value: Double) -> OWLLiteral {
        OWLLiteral(lexicalForm: String(value), datatype: XSDDatatype.decimal.iri)
    }

    /// Create a float literal
    public static func float(_ value: Float) -> OWLLiteral {
        OWLLiteral(lexicalForm: String(value), datatype: XSDDatatype.float.iri)
    }

    /// Create a double literal
    public static func double(_ value: Double) -> OWLLiteral {
        OWLLiteral(lexicalForm: String(value), datatype: XSDDatatype.double.iri)
    }

    /// Create a boolean literal
    public static func boolean(_ value: Bool) -> OWLLiteral {
        OWLLiteral(lexicalForm: value ? "true" : "false", datatype: XSDDatatype.boolean.iri)
    }

    /// Create a date literal (ISO 8601 format)
    public static func date(_ value: Date) -> OWLLiteral {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return OWLLiteral(lexicalForm: formatter.string(from: value), datatype: XSDDatatype.date.iri)
    }

    /// Create a dateTime literal (ISO 8601 format)
    public static func dateTime(_ value: Date) -> OWLLiteral {
        let formatter = ISO8601DateFormatter()
        return OWLLiteral(lexicalForm: formatter.string(from: value), datatype: XSDDatatype.dateTime.iri)
    }

    /// Create a language-tagged string
    public static func langString(_ value: String, language: String) -> OWLLiteral {
        OWLLiteral(lexicalForm: value, datatype: "rdf:langString", language: language)
    }

    /// Create a literal with custom datatype
    public static func typed(_ value: String, datatype: String) -> OWLLiteral {
        OWLLiteral(lexicalForm: value, datatype: datatype)
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
        switch lexicalForm.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }

    /// Try to extract as Date
    public var dateValue: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: lexicalForm)
    }

    /// String value (always available)
    public var stringValue: String {
        lexicalForm
    }
}

// MARK: - XSD Datatypes

/// Common XSD datatypes
public enum XSDDatatype: String, Sendable, CaseIterable {
    // Primitive types
    case string = "xsd:string"
    case boolean = "xsd:boolean"
    case decimal = "xsd:decimal"
    case float = "xsd:float"
    case double = "xsd:double"
    case duration = "xsd:duration"
    case dateTime = "xsd:dateTime"
    case time = "xsd:time"
    case date = "xsd:date"
    case anyURI = "xsd:anyURI"
    case base64Binary = "xsd:base64Binary"
    case hexBinary = "xsd:hexBinary"

    // Derived string types
    case normalizedString = "xsd:normalizedString"
    case token = "xsd:token"
    case language = "xsd:language"
    case nmtoken = "xsd:NMTOKEN"
    case name = "xsd:Name"
    case ncname = "xsd:NCName"

    // Derived numeric types
    case integer = "xsd:integer"
    case nonPositiveInteger = "xsd:nonPositiveInteger"
    case negativeInteger = "xsd:negativeInteger"
    case nonNegativeInteger = "xsd:nonNegativeInteger"
    case positiveInteger = "xsd:positiveInteger"
    case long = "xsd:long"
    case int = "xsd:int"
    case short = "xsd:short"
    case byte = "xsd:byte"
    case unsignedLong = "xsd:unsignedLong"
    case unsignedInt = "xsd:unsignedInt"
    case unsignedShort = "xsd:unsignedShort"
    case unsignedByte = "xsd:unsignedByte"

    /// Full IRI for the datatype
    public var iri: String { rawValue }

    /// Full expanded IRI
    public var expandedIRI: String {
        rawValue.replacingOccurrences(of: "xsd:", with: "http://www.w3.org/2001/XMLSchema#")
    }
}

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
}

// MARK: - CustomStringConvertible

extension OWLLiteral: CustomStringConvertible {
    public var description: String {
        if let lang = language {
            return "\"\(lexicalForm)\"@\(lang)"
        } else if datatype == XSDDatatype.string.iri {
            return "\"\(lexicalForm)\""
        } else {
            return "\"\(lexicalForm)\"^^<\(datatype)>"
        }
    }
}
