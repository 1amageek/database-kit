import DatabaseTypes
// RDFSyntax.swift
// Graph - shared concrete RDF syntax helpers

import DatabaseValue

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
            return "<\(escapeIRI(value.rawValue))>"
        case .blankNode(let id):
            return "_:\(id.rawValue)"
        case .literal(let literal):
            return formatLiteral(literal, usePrefixes: false, prefixes: [:])
        case .tripleTerm(let subject, let predicate, let object):
            return "<<( \(formatNQuadsTerm(subject.term)) \(formatNQuadsTerm(predicate.term)) \(formatNQuadsTerm(object)) )>>"
        }
    }

    static func formatTriGTerm(_ term: RDFTerm, prefixes: [String: String]) -> String {
        switch term {
        case .iri(let value):
            return compactIRI(value.rawValue, prefixes: prefixes)
                ?? "<\(escapeIRI(value.rawValue))>"
        case .blankNode(let id):
            return "_:\(id.rawValue)"
        case .literal(let literal):
            return formatLiteral(literal, usePrefixes: true, prefixes: prefixes)
        case .tripleTerm(let subject, let predicate, let object):
            return "<<( \(formatTriGTerm(subject.term, prefixes: prefixes)) \(formatTriGTerm(predicate.term, prefixes: prefixes)) \(formatTriGTerm(object, prefixes: prefixes)) )>>"
        }
    }

    static func formatLiteral(
        _ literal: RDFLiteral,
        usePrefixes: Bool,
        prefixes: [String: String]
    ) -> String {
        var result = "\"\(escapeString(literal.lexicalForm))\""
        if let language = literal.languageTag {
            result += "@\(language.rawValue)"
            if let direction = literal.baseDirection {
                result += "--\(direction.rawValue)"
            }
            return result
        }

        let datatype = literal.datatypeIRI.rawValue
        if datatype == xsdString || datatype == expandedXSDString {
            return result
        }

        if usePrefixes, let compact = compactIRI(datatype, prefixes: prefixes) {
            result += "^^\(compact)"
        } else if UTF8Text.contains(":", in: datatype),
                  !UTF8Text.contains("://", in: datatype),
                  !datatype.hasPrefix("urn:") {
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
        escape(value, escapesQuotationMark: false, escapesClosingAngle: true)
    }

    static func unescapeIRI(_ value: String) -> String {
        unescapeString(value)
    }

    static func escapeString(_ value: String) -> String {
        escape(value, escapesQuotationMark: true, escapesClosingAngle: false)
    }

    private static func escape(
        _ value: String,
        escapesQuotationMark: Bool,
        escapesClosingAngle: Bool
    ) -> String {
        var escapeCount = 0
        for character in value {
            switch character {
            case "\\", "\n", "\r", "\t":
                escapeCount += 1
            case "\"" where escapesQuotationMark:
                escapeCount += 1
            case ">" where escapesClosingAngle:
                escapeCount += 1
            default:
                continue
            }
        }
        let (capacity, overflow) = value.utf8.count
            .addingReportingOverflow(escapeCount)
        precondition(!overflow, "Escaped RDF text exceeds the supported size")

        var result = ""
        result.reserveCapacity(capacity)
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\"" where escapesQuotationMark:
                result += "\\\""
            case ">" where escapesClosingAngle:
                result += "\\>"
            default:
                result.append(character)
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
