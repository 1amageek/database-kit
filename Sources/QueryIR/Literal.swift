import DatabaseTypes

/// Literal.swift
/// Unified literal value representation for SQL and SPARQL
///
/// Reference:
/// - ISO/IEC 9075:2023 (SQL literals)
/// - W3C SPARQL 1.1/1.2 (RDF literals)
/// - W3C RDF-star (quoted triples)


import DatabaseValue

/// Unified literal value representation
/// Combines SQL literals and SPARQL RDF terms
public enum Literal: Sendable, Equatable, Hashable {
    // MARK: - Common Literals

    /// NULL / UNDEF
    case null

    /// Boolean value
    case bool(Bool)

    /// Integer value (64-bit)
    case int(Int64)

    /// Unsigned integer value (64-bit)
    case uint(UInt64)

    /// Exact base-10 decimal value.
    case decimal(ExactDecimal)

    /// Floating-point value
    case double(Double)

    /// String value
    case string(String)

    /// Date value (date only, no time)
    case date(CivilDate)

    /// Timestamp value (date + time)
    case timestamp(Timestamp)

    /// Binary data
    case binary(ByteString)

    /// Universally unique identifier
    case uuid(DatabaseTypes.UUID)

    /// Array of literals
    case array([Literal])

    // MARK: - SPARQL/RDF-Specific Literals

    /// IRI (Internationalized Resource Identifier)
    /// Example: <http://example.org/resource>
    case iri(String)

    /// Blank node identifier
    /// Example: _:b1
    case blankNode(String)

    /// Typed literal with explicit datatype
    /// Example: "42"^^xsd:integer
    case typedLiteral(value: String, datatype: String)

    /// Language-tagged literal
    /// Example: "Hello"@en
    case langLiteral(value: String, language: String)

    /// Language-tagged literal with base direction (SPARQL 1.2)
    /// Example: "مرحبا"@ar--rtl
    case dirLangLiteral(value: String, language: String, direction: String)

    /// Canonical RDF term, including RDF-star and reified triple terms.
    case rdfTerm(RDFTerm)
}

extension Literal {
    public static func decimal(
        coefficient: Int128,
        scale: Int32
    ) -> Self {
        .decimal(ExactDecimal(coefficient: coefficient, scale: scale))
    }
}

// MARK: - Type Accessors

extension Literal {
    /// Returns true if this literal is NULL
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Returns the boolean value if this is a bool literal
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    /// Returns the integer value if this is an int literal
    public var intValue: Int64? {
        if case .int(let v) = self { return v }
        return nil
    }

    public var uintValue: UInt64? {
        if case .uint(let v) = self { return v }
        return nil
    }

    /// Returns the double value if this is a double literal
    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        return nil
    }

    /// Returns the string value if this is a string literal
    public var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .typedLiteral(let v, _): return v
        case .langLiteral(let v, _): return v
        case .dirLangLiteral(let v, _, _): return v
        case .rdfTerm(let term):
            guard case .literal(let literal) = term else { return nil }
            return literal.lexicalForm
        default: return nil
        }
    }

    /// Returns the IRI string if this is an IRI literal
    public var iriValue: String? {
        if case .iri(let v) = self { return v }
        return nil
    }
}

// MARK: - XSD Datatype Support

extension Literal {
    /// Standard XSD datatype IRIs
    public enum XSDDatatype: String, Sendable {
        case string = "http://www.w3.org/2001/XMLSchema#string"
        case boolean = "http://www.w3.org/2001/XMLSchema#boolean"
        case integer = "http://www.w3.org/2001/XMLSchema#integer"
        case unsignedLong = "http://www.w3.org/2001/XMLSchema#unsignedLong"
        case decimal = "http://www.w3.org/2001/XMLSchema#decimal"
        case double = "http://www.w3.org/2001/XMLSchema#double"
        case float = "http://www.w3.org/2001/XMLSchema#float"
        case date = "http://www.w3.org/2001/XMLSchema#date"
        case dateTime = "http://www.w3.org/2001/XMLSchema#dateTime"
        case time = "http://www.w3.org/2001/XMLSchema#time"
        case duration = "http://www.w3.org/2001/XMLSchema#duration"
        case anyURI = "http://www.w3.org/2001/XMLSchema#anyURI"
        case base64Binary = "http://www.w3.org/2001/XMLSchema#base64Binary"
        case hexBinary = "http://www.w3.org/2001/XMLSchema#hexBinary"
    }

    /// Create a typed literal with XSD datatype
    public static func xsd(_ value: String, type: XSDDatatype) -> Literal {
        .typedLiteral(value: value, datatype: type.rawValue)
    }

    /// Returns the XSD datatype of this literal, if applicable
    public var xsdDatatype: XSDDatatype? {
        switch self {
        case .bool:
            return .boolean
        case .int:
            return .integer
        case .uint:
            return .unsignedLong
        case .decimal:
            return .decimal
        case .double:
            return .double
        case .string:
            return .string
        case .date:
            return .date
        case .timestamp:
            return .dateTime
        case .binary:
            return .base64Binary
        case .uuid:
            return nil
        case .typedLiteral(_, let datatype):
            return XSDDatatype(rawValue: datatype)
        case .rdfTerm(let term):
            guard case .literal(let literal) = term else { return nil }
            return XSDDatatype(rawValue: literal.datatypeIRI.rawValue)
        default:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension Literal: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "NULL"
        case .bool(let v):
            return v ? "true" : "false"
        case .int(let v):
            return String(v)
        case .uint(let v):
            return String(v)
        case .decimal(let value):
            return DatabaseLiteralEncoding.decimal(value)
        case .double(let v):
            return String(v)
        case .string(let v):
            return "\"\(v)\""
        case .date(let v):
            return DatabaseLiteralEncoding.iso8601(v)
        case .timestamp(let v):
            return DatabaseLiteralEncoding.iso8601(v)
        case .binary(let v):
            return "binary(\(v.count) bytes)"
        case .uuid(let v):
            return v.description
        case .array(let v):
            return "[\(v.map { $0.description }.joined(separator: ", "))]"
        case .iri(let v):
            return "<\(v)>"
        case .blankNode(let v):
            return "_:\(v)"
        case .typedLiteral(let value, let datatype):
            return "\"\(value)\"^^<\(datatype)>"
        case .langLiteral(let value, let language):
            return "\"\(value)\"@\(language)"
        case .dirLangLiteral(let value, let language, let direction):
            return "\"\(value)\"@\(language)--\(direction)"
        case .rdfTerm(let term):
            return term.description
        }
    }
}
