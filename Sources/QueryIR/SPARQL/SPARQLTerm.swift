/// SPARQLTerm.swift
/// SPARQL term types (RDF terms)
///
/// Reference:
/// - W3C SPARQL 1.1/1.2 Query Language
/// - W3C RDF 1.1 Concepts
/// - W3C RDF-star

import DatabaseValue

// Note: Core SPARQLTerm enum is defined in DataSource.swift
// This file provides additional utilities and extensions.

// MARK: - SPARQLTerm Builders

extension SPARQLTerm {
    /// Create a variable term
    public static func `var`(_ name: String) -> SPARQLTerm {
        .variable(name)
    }

    /// Create an IRI term
    public static func uri(_ iri: String) -> SPARQLTerm {
        .iri(iri)
    }

    /// Create a string literal term
    public static func string(_ value: String) -> SPARQLTerm {
        .literal(.string(value))
    }

    /// Create an integer literal term
    public static func int(_ value: Int64) -> SPARQLTerm {
        .literal(.int(value))
    }

    /// Create a double literal term
    public static func double(_ value: Double) -> SPARQLTerm {
        .literal(.double(value))
    }

    /// Create a boolean literal term
    public static func bool(_ value: Bool) -> SPARQLTerm {
        .literal(.bool(value))
    }

    /// Create a typed literal term
    public static func typed(_ value: String, datatype: String) -> SPARQLTerm {
        .literal(.typedLiteral(value: value, datatype: datatype))
    }

    /// Create a language-tagged literal term
    public static func lang(_ value: String, language: String) -> SPARQLTerm {
        .literal(.langLiteral(value: value, language: language))
    }

    /// Create a blank node term
    public static func blank(_ id: String) -> SPARQLTerm {
        .blankNode(id)
    }

    /// Create a quoted triple term (RDF-star)
    public static func quoted(
        subject: SPARQLTerm,
        predicate: SPARQLTerm,
        object: SPARQLTerm
    ) -> SPARQLTerm {
        .tripleTerm(subject: subject, predicate: predicate, object: object)
    }
}

// MARK: - SPARQLTerm Analysis

extension SPARQLTerm {
    /// Returns true if this is a variable
    public var isVariable: Bool {
        if case .variable = self { return true }
        return false
    }

    /// Returns true if this is a concrete term (not a variable)
    public var isConcrete: Bool {
        !isVariable
    }

    /// Returns true if this is an IRI
    public var isIRI: Bool {
        if case .iri = self { return true }
        return false
    }

    /// Returns true if this is a literal
    public var isLiteral: Bool {
        if case .literal = self { return true }
        return false
    }

    /// Returns true if this is a blank node
    public var isBlankNode: Bool {
        if case .blankNode = self { return true }
        return false
    }

    /// Returns true if this is a quoted triple (RDF-star)
    public var isQuotedTriple: Bool {
        if case .tripleTerm = self { return true }
        return false
    }

    /// Returns the variable name if this is a variable
    public var variableName: String? {
        if case .variable(let name) = self { return name }
        return nil
    }

    /// Returns the canonical absolute IRI string when this is an IRI.
    public var iriValue: String? {
        if case .iri(let iri) = self { return iri }
        return nil
    }

    /// Returns the literal value if this is a literal
    public var literalValue: Literal? {
        if case .literal(let lit) = self { return lit }
        return nil
    }
}

// MARK: - SPARQL Serialization

extension SPARQLTerm {
    /// Generate SPARQL syntax with proper escaping
    public func toSPARQL(prefixes: [String: String] = [:]) -> String {
        switch self {
        case .variable(let name):
            return "?\(name)"

        case .iri(let iri):
            // Try to abbreviate with prefix
            for (prefix, base) in prefixes {
                if iri.hasPrefix(base) {
                    let local = String(iri.dropFirst(base.count))
                    // Validate NCName for both prefix and local
                    if SPARQLEscape.ncNameOrNil(prefix) != nil,
                       local.isEmpty || SPARQLEscape.ncNameOrNil(local) != nil {
                        return "\(prefix):\(local)"
                    }
                }
            }
            // Fall back to full IRI with proper escaping
            return SPARQLEscape.iri(iri)

        case .literal(let lit):
            return lit.toSPARQL()

        case .blankNode(let id):
            // Validate blank node ID
            if SPARQLEscape.ncNameOrNil(id) != nil {
                return "_:\(id)"
            }
            // Generate safe blank node ID
            return "_:b\(abs(id.hashValue))"

        case .tripleTerm(let s, let p, let o):
            return "<< \(s.toSPARQL(prefixes: prefixes)) \(p.toSPARQL(prefixes: prefixes)) \(o.toSPARQL(prefixes: prefixes)) >>"

        case .reifiedTriple(let s, let p, let o, let r):
            return "<< \(s.toSPARQL(prefixes: prefixes)) \(p.toSPARQL(prefixes: prefixes)) \(o.toSPARQL(prefixes: prefixes)) ~\(r.toSPARQL(prefixes: prefixes)) >>"
        }
    }
}

extension Literal {
    /// Generate SPARQL literal syntax
    public func toSPARQL() -> String {
        switch self {
        case .null:
            return "UNDEF"
        case .bool(let v):
            return v ? "true" : "false"
        case .int(let v):
            return String(v)
        case .uint(let v):
            return "\"\(v)\"^^<http://www.w3.org/2001/XMLSchema#unsignedLong>"
        case .decimal(let coefficient, let scale):
            return "\"\(DatabaseLiteralEncoding.decimal(coefficient: coefficient, scale: scale))\"^^<urn:database:decimal>"
        case .double(let v):
            return String(v)
        case .string(let v):
            return SPARQLEscape.string(v)
        case .date(let v):
            return "\"\(DatabaseLiteralEncoding.iso8601(v))\"^^<http://www.w3.org/2001/XMLSchema#date>"
        case .timestamp(let v):
            return "\"\(DatabaseLiteralEncoding.iso8601(v))\"^^<http://www.w3.org/2001/XMLSchema#dateTime>"
        case .binary(let v):
            return "\"\(DatabaseLiteralEncoding.base64(v))\"^^<http://www.w3.org/2001/XMLSchema#base64Binary>"
        case .uuid(let v):
            return "\"\(v.description)\"^^<urn:uuid>"
        case .array(let v):
            return "(" + v.map { $0.toSPARQL() }.joined(separator: " ") + ")"
        case .iri(let v):
            return SPARQLEscape.iri(v)
        case .blankNode(let v):
            if SPARQLEscape.ncNameOrNil(v) != nil {
                return "_:\(v)"
            }
            return "_:b\(abs(v.hashValue))"
        case .typedLiteral(let value, let datatype):
            return "\(SPARQLEscape.string(value))^^<\(datatype)>"
        case .langLiteral(let value, let language):
            return "\(SPARQLEscape.string(value))@\(language)"
        case .dirLangLiteral(let value, let language, let direction):
            return "\(SPARQLEscape.string(value))@\(language)--\(direction)"
        case .rdfTerm(let term):
            return Self.rdfTermSPARQL(term)
        }
    }

    private static func rdfTermSPARQL(_ term: DatabaseRDFTerm) -> String {
        switch term {
        case .iri(let value):
            return SPARQLEscape.iri(value)
        case .blankNode(let identifier):
            if SPARQLEscape.ncNameOrNil(identifier) != nil {
                return "_:\(identifier)"
            }
            var hash = UInt64(14_695_981_039_346_656_037)
            for byte in identifier.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            return "_:b\(hash)"
        case .literal(let literal):
            let lexical = SPARQLEscape.string(literal.lexicalForm)
            if let language = literal.language {
                if let direction = literal.direction {
                    return "\(lexical)@\(language)--\(direction)"
                }
                return "\(lexical)@\(language)"
            }
            return "\(lexical)^^<\(literal.datatype)>"
        case .tripleTerm(let subject, let predicate, let object):
            return "<<( \(rdfTermSPARQL(subject)) \(rdfTermSPARQL(predicate)) \(rdfTermSPARQL(object)) )>>"
        }
    }
}

// MARK: - Common Prefixes

extension SPARQLTerm {
    /// Common RDF/RDFS/OWL prefixes
    public static let commonPrefixes: [String: String] = [
        "rdf": "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "owl": "http://www.w3.org/2002/07/owl#",
        "xsd": "http://www.w3.org/2001/XMLSchema#",
        "foaf": "http://xmlns.com/foaf/0.1/",
        "dc": "http://purl.org/dc/elements/1.1/",
        "dcterms": "http://purl.org/dc/terms/",
        "schema": "http://schema.org/",
        "skos": "http://www.w3.org/2004/02/skos/core#"
    ]

    /// RDF type property
    public static var rdfType: SPARQLTerm {
        .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
    }

    /// RDFS label property
    public static var rdfsLabel: SPARQLTerm {
        .iri("http://www.w3.org/2000/01/rdf-schema#label")
    }

    /// RDFS comment property
    public static var rdfsComment: SPARQLTerm {
        .iri("http://www.w3.org/2000/01/rdf-schema#comment")
    }

    /// RDFS subClassOf property
    public static var rdfsSubClassOf: SPARQLTerm {
        .iri("http://www.w3.org/2000/01/rdf-schema#subClassOf")
    }

    /// RDFS subPropertyOf property
    public static var rdfsSubPropertyOf: SPARQLTerm {
        .iri("http://www.w3.org/2000/01/rdf-schema#subPropertyOf")
    }

    /// OWL sameAs property
    public static var owlSameAs: SPARQLTerm {
        .iri("http://www.w3.org/2002/07/owl#sameAs")
    }

    /// OWL Class
    public static var owlClass: SPARQLTerm {
        .iri("http://www.w3.org/2002/07/owl#Class")
    }
}

// MARK: - Term Comparison

extension SPARQLTerm {
    /// Compare two terms for SPARQL ordering
    /// Returns: negative if self < other, zero if equal, positive if self > other
    public func compare(to other: SPARQLTerm, prefixes: [String: String] = [:]) -> Int {
        // SPARQL term ordering:
        // 1. Blank nodes
        // 2. IRIs
        // 3. Literals

        let selfRank = termRank
        let otherRank = other.termRank

        if selfRank != otherRank {
            return selfRank - otherRank
        }

        // Same type, compare values
        switch (self, other) {
        case (.blankNode(let a), .blankNode(let b)):
            return a < b ? -1 : (a == b ? 0 : 1)

        case (.iri(let a), .iri(let b)):
            return a < b ? -1 : (a == b ? 0 : 1)

        case (.literal(let a), .literal(let b)):
            return compareLiterals(a, b)

        case (.variable(let a), .variable(let b)):
            return a < b ? -1 : (a == b ? 0 : 1)

        default:
            return 0
        }
    }

    private var termRank: Int {
        switch self {
        case .blankNode: return 1
        case .iri: return 2
        case .literal: return 3
        case .variable: return 0
        case .tripleTerm: return 4
        case .reifiedTriple: return 5
        }
    }

    private func compareLiterals(_ a: Literal, _ b: Literal) -> Int {
        if let numericComparison = a.compareExactNumeric(to: b) {
            return numericComparison
        }
        let aStr = a.description
        let bStr = b.description
        return aStr < bStr ? -1 : (aStr == bStr ? 0 : 1)
    }
}

// MARK: - Expression Conversion

extension SPARQLTerm {
    /// Convert to an Expression
    public func toExpression() -> Expression {
        switch self {
        case .variable(let name):
            return .variable(Variable(name))
        case .literal(let lit):
            return .literal(lit)
        case .iri(let iri):
            return .literal(.iri(iri))
        case .blankNode(let id):
            return .literal(.blankNode(id))
        case .tripleTerm(let s, let p, let o):
            return .triple(
                subject: s.toExpression(),
                predicate: p.toExpression(),
                object: o.toExpression()
            )
        case .reifiedTriple(let s, let p, let o, _):
            return .triple(
                subject: s.toExpression(),
                predicate: p.toExpression(),
                object: o.toExpression()
            )
        }
    }
}
