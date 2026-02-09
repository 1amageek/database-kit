// RDFTerm.swift
// Graph - RDF term encoding for graph index storage
//
// Provides typed RDF term representation following the N-Triples encoding
// convention (W3C RDF 1.1 N-Triples). Graph index String fields use this
// encoding to preserve node type information (IRI / Literal / Blank Node).
//
// Encoding rules:
//   IRI:          stored as-is              "ex:Alice", "http://example.org/Person"
//   Literal:      quoted with optional type  "\"Alice\"", "\"30\"^^xsd:integer", "\"hello\"@en"
//   Blank node:   _: prefix                  "_:b1"
//
// Reference: W3C RDF 1.1 N-Triples
// https://www.w3.org/TR/n-triples/

import Foundation

/// RDF Term with node type information
///
/// Represents an RDF node (IRI, Literal, or Blank Node) and provides
/// encoding/decoding for storage in graph index String fields.
///
/// **Usage**:
/// ```swift
/// // Creating RDF terms
/// let iri = RDFTerm.iri("ex:Alice")
/// let name = RDFTerm.literal("Alice")
/// let age = RDFTerm.literal("30", datatype: "xsd:integer")
/// let label = RDFTerm.literal("hello", language: "en")
/// let blank = RDFTerm.blankNode("b1")
///
/// // Encoding for graph index storage
/// var stmt = Statement()
/// stmt.subject = RDFTerm.iri("ex:Alice").encoded
/// stmt.predicate = RDFTerm.iri("ex:name").encoded
/// stmt.object = RDFTerm.literal("Alice").encoded
///
/// // Decoding from graph index
/// let term = RDFTerm.decode(stmt.object)
/// // → .literal("Alice", datatype: "xsd:string", language: nil)
/// ```
public enum RDFTerm: Sendable, Hashable, Codable {
    /// IRI reference (e.g., "ex:Alice", "http://example.org/Person")
    case iri(String)

    /// Literal value with optional datatype and language tag
    ///
    /// - Parameters:
    ///   - lexicalForm: The string content of the literal
    ///   - datatype: XSD datatype IRI (defaults to "xsd:string" when encoded)
    ///   - language: BCP 47 language tag (e.g., "en", "ja")
    case literal(String, datatype: String? = nil, language: String? = nil)

    /// Blank node identifier (e.g., "b1")
    case blankNode(String)

    // MARK: - Encoding

    /// Encode to string for storage in graph index String fields
    ///
    /// Follows N-Triples encoding convention:
    /// - IRI: stored as-is (no brackets in compact form)
    /// - Literal: `"value"`, `"value"^^datatype`, `"value"@lang`
    /// - Blank node: `_:id`
    public var encoded: String {
        switch self {
        case .iri(let value):
            return value
        case .literal(let lexicalForm, let datatype, let language):
            var result = "\"\(Self.escapeNTriples(lexicalForm))\""
            if let language {
                result += "@\(language)"
            } else if let datatype {
                result += "^^\(datatype)"
            }
            return result
        case .blankNode(let id):
            return "_:\(id)"
        }
    }

    // MARK: - Decoding

    /// Decode from a string stored in graph index
    ///
    /// Parsing rules:
    /// 1. Starts with `"` → Literal (parse quoted string, optional ^^datatype or @lang)
    /// 2. Starts with `_:` → Blank node
    /// 3. Otherwise → IRI
    public static func decode(_ string: String) -> RDFTerm {
        if string.hasPrefix("\"") {
            return parseLiteral(string)
        }
        if string.hasPrefix("_:") {
            return .blankNode(String(string.dropFirst(2)))
        }
        return .iri(string)
    }

    // MARK: - SHACLValue Conversion

    /// Convert to SHACLValue for SHACL constraint evaluation
    public func toSHACLValue() -> SHACLValue {
        switch self {
        case .iri(let value):
            return .iri(value)
        case .literal(let lexicalForm, let datatype, let language):
            let dt = datatype ?? "xsd:string"
            return .literal(OWLLiteral(lexicalForm: lexicalForm, datatype: dt, language: language))
        case .blankNode(let id):
            return .blankNode(id)
        }
    }

    // MARK: - Convenience Constructors

    /// Create a typed string literal
    public static func string(_ value: String) -> RDFTerm {
        .literal(value, datatype: "xsd:string")
    }

    /// Create a typed integer literal
    public static func integer(_ value: Int) -> RDFTerm {
        .literal(String(value), datatype: "xsd:integer")
    }

    /// Create a typed decimal literal
    public static func decimal(_ value: Double) -> RDFTerm {
        .literal(String(value), datatype: "xsd:decimal")
    }

    /// Create a typed boolean literal
    public static func boolean(_ value: Bool) -> RDFTerm {
        .literal(value ? "true" : "false", datatype: "xsd:boolean")
    }

    /// Create a language-tagged string literal
    public static func langString(_ value: String, language: String) -> RDFTerm {
        .literal(value, datatype: "rdf:langString", language: language)
    }

    // MARK: - Private

    /// Escape special characters for N-Triples string encoding
    ///
    /// Reference: W3C N-Triples §2.3.2 (STRING_LITERAL_QUOTE)
    private static func escapeNTriples(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(ch)
            }
        }
        return result
    }

    /// Unescape N-Triples string encoding
    private static func unescapeNTriples(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        var iter = s.makeIterator()
        while let ch = iter.next() {
            if ch == "\\" {
                guard let escaped = iter.next() else {
                    result.append(ch)
                    break
                }
                switch escaped {
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default:
                    result.append("\\")
                    result.append(escaped)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    /// Parse a literal from N-Triples encoding
    ///
    /// Expected formats:
    /// - `"value"`
    /// - `"value"^^datatype`
    /// - `"value"@lang`
    private static func parseLiteral(_ s: String) -> RDFTerm {
        // Must start with "
        guard s.hasPrefix("\"") else { return .iri(s) }

        // Find the closing quote (handling escaped quotes)
        var i = s.index(after: s.startIndex)
        var lexical = ""
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let next = s.index(after: i)
                if next < s.endIndex {
                    lexical.append(ch)
                    lexical.append(s[next])
                    i = s.index(after: next)
                    continue
                }
            }
            if ch == "\"" {
                break
            }
            lexical.append(ch)
            i = s.index(after: i)
        }

        let unescaped = unescapeNTriples(lexical)

        // Check what follows the closing quote
        let afterQuote = s.index(after: i)
        if afterQuote >= s.endIndex {
            // Plain literal: "value" (no explicit datatype)
            return .literal(unescaped)
        }

        let suffix = s[afterQuote...]
        if suffix.hasPrefix("^^") {
            // Typed literal: "value"^^datatype
            let datatypeStr = String(suffix.dropFirst(2))
            return .literal(unescaped, datatype: datatypeStr)
        }
        if suffix.hasPrefix("@") {
            // Language-tagged literal: "value"@lang
            // W3C RDF: language-tagged literals always have rdf:langString datatype
            let lang = String(suffix.dropFirst(1))
            return .literal(unescaped, datatype: "rdf:langString", language: lang)
        }

        return .literal(unescaped)
    }
}

// MARK: - CustomStringConvertible

extension RDFTerm: CustomStringConvertible {
    public var description: String {
        encoded
    }
}
