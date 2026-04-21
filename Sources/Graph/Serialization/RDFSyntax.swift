// RDFSyntax.swift
// Graph - shared concrete RDF syntax helpers

import Foundation

public enum RDFSyntaxError: Error, Sendable, Equatable, CustomStringConvertible {
    case unexpectedToken(expected: String, found: String, line: Int)
    case unexpectedEndOfInput(expected: String)
    case unterminatedString(line: Int)
    case invalidIRI(String, line: Int)
    case undefinedPrefix(String, line: Int)
    case invalidTerm(String, line: Int)
    case invalidQuad(String, line: Int)

    public var description: String {
        switch self {
        case .unexpectedToken(let expected, let found, let line):
            return "Expected \(expected), found \(found) at line \(line)"
        case .unexpectedEndOfInput(let expected):
            return "Unexpected end of input; expected \(expected)"
        case .unterminatedString(let line):
            return "Unterminated string literal at line \(line)"
        case .invalidIRI(let iri, let line):
            return "Invalid IRI '\(iri)' at line \(line)"
        case .undefinedPrefix(let prefix, let line):
            return "Undefined prefix '\(prefix)' at line \(line)"
        case .invalidTerm(let term, let line):
            return "Invalid RDF term '\(term)' at line \(line)"
        case .invalidQuad(let reason, let line):
            return "Invalid RDF quad at line \(line): \(reason)"
        }
    }
}

enum RDFSyntaxFormatter {
    static let xsdString = "xsd:string"
    static let expandedXSDString = "http://www.w3.org/2001/XMLSchema#string"
    static let rdfLangString = "rdf:langString"
    static let expandedRDFLangString = "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

    static func formatNQuadsTerm(_ term: RDFTerm) -> String {
        switch term {
        case .iri(let value):
            return "<\(escapeIRI(value))>"
        case .blankNode(let id):
            return "_:\(id)"
        case .literal(let literal):
            return formatLiteral(literal, usePrefixes: false, prefixes: [:])
        }
    }

    static func formatTriGTerm(_ term: RDFTerm, prefixes: [String: String]) -> String {
        switch term {
        case .iri(let value):
            return compactIRI(value, prefixes: prefixes) ?? "<\(escapeIRI(value))>"
        case .blankNode(let id):
            return "_:\(id)"
        case .literal(let literal):
            return formatLiteral(literal, usePrefixes: true, prefixes: prefixes)
        }
    }

    static func formatLiteral(
        _ literal: OWLLiteral,
        usePrefixes: Bool,
        prefixes: [String: String]
    ) -> String {
        var result = "\"\(escapeString(literal.lexicalForm))\""
        if let language = literal.language {
            result += "@\(language)"
            return result
        }

        let datatype = literal.datatype
        if datatype == xsdString || datatype == expandedXSDString {
            return result
        }

        if usePrefixes, let compact = compactIRI(datatype, prefixes: prefixes) {
            result += "^^\(compact)"
        } else if datatype.contains(":") && !datatype.contains("://") && !datatype.hasPrefix("urn:") {
            result += "^^\(datatype)"
        } else {
            result += "^^<\(escapeIRI(datatype))>"
        }
        return result
    }

    static func compactIRI(_ iri: String, prefixes: [String: String]) -> String? {
        for (prefix, namespace) in prefixes.sorted(by: { $0.key < $1.key }) {
            guard iri.hasPrefix(namespace) else { continue }
            let local = String(iri.dropFirst(namespace.count))
            guard !local.isEmpty else { continue }
            return "\(prefix):\(local)"
        }
        return nil
    }

    static func escapeIRI(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": result += "\\\\"
            case ">": result += "\\>"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(ch)
            }
        }
        return result
    }

    static func unescapeIRI(_ value: String) -> String {
        unescapeString(value)
    }

    static func escapeString(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for ch in value {
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

    static func unescapeString(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            if ch == "\\" {
                guard let escaped = iterator.next() else {
                    result.append(ch)
                    break
                }
                switch escaped {
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case ">": result.append(">")
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
}
