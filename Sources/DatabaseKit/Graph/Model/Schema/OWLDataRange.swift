import DatabaseTypes
// OWLDataRange.swift
// Graph - OWL DL data range definitions
//
// Provides data range types for OWL data properties.
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Data_Ranges

/// OWL Data Range
///
/// Represents the range of values for data properties.
/// Supports XSD datatypes, boolean operations, and facet restrictions.
///
/// **DL Notation**:
/// - `xsd:integer` = datatype("xsd:integer")
/// - `D₁ ∩ D₂` = dataIntersectionOf
/// - `D₁ ∪ D₂` = dataUnionOf
/// - `¬D` = dataComplementOf
/// - `{v₁, v₂, ...}` = dataOneOf
/// - `xsd:integer[≥0, ≤100]` = datatypeRestriction
///
/// **Example**:
/// ```swift
/// // Integer between 0 and 100
/// let ageRange = OWLDataRange.datatypeRestriction(
///     datatype: XSDDatatype.integer.iri,
///     facets: [.minInclusive(0), .maxInclusive(100)]
/// )
///
/// // String with pattern
/// let emailPattern = OWLDataRange.datatypeRestriction(
///     datatype: XSDDatatype.string.iri,
///     facets: [.pattern("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}")]
/// )
/// ```
public indirect enum OWLDataRange: Sendable, Hashable {
    /// Basic datatype (xsd:string, xsd:integer, xsd:boolean, etc.)
    case datatype(String)

    /// Intersection of data ranges (D₁ ∩ D₂)
    case dataIntersectionOf([OWLDataRange])

    /// Union of data ranges (D₁ ∪ D₂)
    case dataUnionOf([OWLDataRange])

    /// Complement of a data range (¬D)
    case dataComplementOf(OWLDataRange)

    /// Enumeration of literal values ({v₁, v₂, ...})
    case dataOneOf([RDFLiteral])

    /// Datatype with facet restrictions
    case datatypeRestriction(datatype: String, facets: [FacetRestriction])
}

// MARK: - Convenience Constructors

extension OWLDataRange {
    /// Create a string datatype range
    public static var string: OWLDataRange {
        .datatype(XSDDatatype.string.iri.rawValue)
    }

    /// Create an integer datatype range
    public static var integer: OWLDataRange {
        .datatype(XSDDatatype.integer.iri.rawValue)
    }

    /// Create a boolean datatype range
    public static var boolean: OWLDataRange {
        .datatype(XSDDatatype.boolean.iri.rawValue)
    }

    /// Create a decimal datatype range
    public static var decimal: OWLDataRange {
        .datatype(XSDDatatype.decimal.iri.rawValue)
    }

    /// Create a double datatype range
    public static var double: OWLDataRange {
        .datatype(XSDDatatype.double.iri.rawValue)
    }

    /// Create a float datatype range
    public static var float: OWLDataRange {
        .datatype(XSDDatatype.float.iri.rawValue)
    }

    /// Create a date datatype range
    public static var date: OWLDataRange {
        .datatype(XSDDatatype.date.iri.rawValue)
    }

    /// Create a dateTime datatype range
    public static var dateTime: OWLDataRange {
        .datatype(XSDDatatype.dateTime.iri.rawValue)
    }

    /// Create an anyURI datatype range
    public static var anyURI: OWLDataRange {
        .datatype(XSDDatatype.anyURI.iri.rawValue)
    }

    /// Create an integer range with min/max bounds
    public static func integerRange(min: Int? = nil, max: Int? = nil) -> OWLDataRange {
        var facets: [FacetRestriction] = []
        if let min = min {
            facets.append(.minInclusive(min))
        }
        if let max = max {
            facets.append(.maxInclusive(max))
        }
        return .datatypeRestriction(
            datatype: XSDDatatype.integer.iri.rawValue,
            facets: facets
        )
    }

    /// Create a string range with length constraints
    public static func stringLength(min: Int? = nil, max: Int? = nil) -> OWLDataRange {
        var facets: [FacetRestriction] = []
        if let min = min {
            facets.append(.minLength(min))
        }
        if let max = max {
            facets.append(.maxLength(max))
        }
        return .datatypeRestriction(
            datatype: XSDDatatype.string.iri.rawValue,
            facets: facets
        )
    }

    /// Create a string range with pattern constraint
    public static func stringPattern(_ regex: String) -> OWLDataRange {
        .datatypeRestriction(
            datatype: XSDDatatype.string.iri.rawValue,
            facets: [.pattern(regex)]
        )
    }
}

// MARK: - Analysis

extension OWLDataRange {
    /// Check if this range is a simple datatype (no restrictions)
    public var isSimpleDatatype: Bool {
        switch self {
        case .datatype:
            return true
        default:
            return false
        }
    }

    /// Get the base datatype (if applicable)
    public var baseDatatype: String? {
        switch self {
        case .datatype(let dt):
            return dt
        case .datatypeRestriction(let dt, _):
            return dt
        default:
            return nil
        }
    }

}

// MARK: - CustomStringConvertible

extension OWLDataRange: CustomStringConvertible {
    public var description: String {
        switch self {
        case .datatype(let iri):
            return iri

        case .dataIntersectionOf(let ranges):
            let rangeStrs = ranges.map { $0.description }
            return "DataIntersectionOf(\(rangeStrs.joined(separator: " ")))"

        case .dataUnionOf(let ranges):
            let rangeStrs = ranges.map { $0.description }
            return "DataUnionOf(\(rangeStrs.joined(separator: " ")))"

        case .dataComplementOf(let range):
            return "DataComplementOf(\(range.description))"

        case .dataOneOf(let literals):
            let literalStrs = literals.map { $0.description }
            return "DataOneOf(\(literalStrs.joined(separator: " ")))"

        case .datatypeRestriction(let dt, let facets):
            let facetStrs = facets.map { "\($0.facet.rawValue) \($0.value.lexicalForm)" }
            return "\(dt)[\(facetStrs.joined(separator: ", "))]"
        }
    }
}
