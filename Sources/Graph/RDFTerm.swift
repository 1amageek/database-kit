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

/// RDF Term — the union of IRI, Literal, and Blank Node.
///
/// Represents an RDF node (W3C RDF 1.1 Concepts) and provides
/// encoding/decoding for storage in graph index String fields.
/// Used across Graph, SHACL, and OWL modules as the single type
/// for RDF node values.
///
/// **Usage**:
/// ```swift
/// let iri = RDFTerm.iri("ex:Alice")
/// let name = RDFTerm.string("Alice")
/// let age = RDFTerm.integer(30)
/// let label = RDFTerm.langString("hello", language: "en")
/// let blank = RDFTerm.blankNode("b1")
///
/// // Encoding for graph index storage
/// stmt.object = RDFTerm.string("Alice").encoded   // → "\"Alice\""
/// stmt.object = RDFTerm.integer(30).encoded        // → "\"30\"^^xsd:integer"
///
/// // Decoding from graph index
/// let term = RDFTerm.decode(stmt.object)
/// ```
public enum RDFTerm: Sendable, Hashable, Codable {
    /// IRI reference (e.g., "ex:Alice", "http://example.org/Person")
    case iri(String)

    /// Literal value with datatype and optional language tag
    case literal(OWLLiteral)

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
        case .literal(let literal):
            var result = "\"\(Self.escapeNTriples(literal.lexicalForm))\""
            if let language = literal.language {
                result += "@\(language)"
            } else if literal.datatype != "xsd:string" {
                result += "^^\(literal.datatype)"
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

    // MARK: - Convenience Constructors

    /// Create a typed string literal
    public static func string(_ value: String) -> RDFTerm {
        .literal(.string(value))
    }

    /// Create a typed integer literal
    public static func integer(_ value: Int) -> RDFTerm {
        .literal(.integer(value))
    }

    /// Create a typed decimal literal
    public static func decimal(_ value: Double) -> RDFTerm {
        .literal(.decimal(value))
    }

    /// Create a typed boolean literal
    public static func boolean(_ value: Bool) -> RDFTerm {
        .literal(.boolean(value))
    }

    /// Create a language-tagged string literal
    public static func langString(_ value: String, language: String) -> RDFTerm {
        .literal(.langString(value, language: language))
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
            // Plain literal: "value" → default xsd:string
            return .literal(OWLLiteral(lexicalForm: unescaped, datatype: "xsd:string"))
        }

        let suffix = s[afterQuote...]
        if suffix.hasPrefix("^^") {
            // Typed literal: "value"^^datatype
            let datatypeStr = String(suffix.dropFirst(2))
            return .literal(OWLLiteral(lexicalForm: unescaped, datatype: datatypeStr))
        }
        if suffix.hasPrefix("@") {
            // Language-tagged literal: "value"@lang
            // W3C RDF: language-tagged literals always have rdf:langString datatype
            let lang = String(suffix.dropFirst(1))
            return .literal(OWLLiteral(lexicalForm: unescaped, datatype: "rdf:langString", language: lang))
        }

        return .literal(OWLLiteral(lexicalForm: unescaped, datatype: "xsd:string"))
    }
}

// MARK: - CustomStringConvertible

extension RDFTerm: CustomStringConvertible {
    public var description: String {
        encoded
    }
}
