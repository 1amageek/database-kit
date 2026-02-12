// TurtleDecoder.swift
// Graph - Turtle (RDF) → OWLOntology decoder
//
// Decodes W3C Turtle syntax into an OWLOntology.
//
// Reference: W3C RDF 1.1 Turtle
// https://www.w3.org/TR/turtle/

import Foundation

/// Decodes a Turtle (RDF) string into an OWLOntology.
///
/// Three-phase processing: Tokenize → Parse → Build OWLOntology.
///
/// ```swift
/// let ontology = try TurtleDecoder().decode(from: turtleString)
/// ```
public struct TurtleDecoder: Sendable {

    public init() {}

    /// Decode a Turtle string into an OWLOntology.
    ///
    /// - Parameter turtle: Turtle format string
    /// - Returns: Decoded OWLOntology
    /// - Throws: TurtleDecodingError
    public func decode(from turtle: String) throws -> OWLOntology {
        let tokenizer = TurtleTokenizer(input: turtle)
        let tokens = try tokenizer.tokenize()
        let parser = TurtleParser(tokens: tokens)
        let (prefixes, triples) = try parser.parse()
        let builder = OWLBuilder(prefixes: prefixes, triples: triples)
        return builder.build()
    }
}

// MARK: - Error

public enum TurtleDecodingError: Error, Sendable, Equatable {
    case unexpectedToken(expected: String, found: String, line: Int)
    case unterminatedString(line: Int)
    case undefinedPrefix(String, line: Int)
    case invalidIRI(String, line: Int)
    case unexpectedEndOfInput
}

// MARK: - Token

private enum TurtleToken: Sendable {
    case prefixDecl         // @prefix
    case baseDecl           // @base
    case sparqlPrefix       // PREFIX
    case sparqlBase         // BASE
    case iri(String)        // <http://...>
    case prefixedName(String) // ex:Person
    case blankNode(String)  // _:label
    case stringLiteral(String) // "text"
    case integerLiteral(String) // 42
    case decimalLiteral(String) // 3.14
    case doubleLiteral(String) // 1.0e10
    case booleanLiteral(String) // true / false
    case a                  // rdf:type shorthand
    case dot                // .
    case semicolon          // ;
    case comma              // ,
    case openBracket        // [
    case closeBracket       // ]
    case openParen          // (
    case closeParen         // )
    case hatHat             // ^^
    case langTag(String)    // @en
    case eof
}

// MARK: - Tokenizer

private final class TurtleTokenizer {
    let input: String
    var index: String.Index
    var line: Int = 1

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    func tokenize() throws -> [TurtleToken] {
        var tokens: [TurtleToken] = []
        while index < input.endIndex {
            skipWhitespaceAndComments()
            guard index < input.endIndex else { break }

            let ch = input[index]

            switch ch {
            case "<":
                tokens.append(try readIRI())
            case "\"":
                tokens.append(try readStringLiteral())
            case "'":
                tokens.append(try readSingleQuotedStringLiteral())
            case ".":
                // Check for decimal literal
                let next = peek(offset: 1)
                if let n = next, n.isNumber {
                    tokens.append(readNumericLiteral())
                } else {
                    advance()
                    tokens.append(.dot)
                }
            case ";":
                advance()
                tokens.append(.semicolon)
            case ",":
                advance()
                tokens.append(.comma)
            case "[":
                advance()
                tokens.append(.openBracket)
            case "]":
                advance()
                tokens.append(.closeBracket)
            case "(":
                advance()
                tokens.append(.openParen)
            case ")":
                advance()
                tokens.append(.closeParen)
            case "^":
                if peek(offset: 1) == "^" {
                    advance()
                    advance()
                    tokens.append(.hatHat)
                } else {
                    throw TurtleDecodingError.unexpectedToken(expected: "^^", found: String(ch), line: line)
                }
            case "@":
                advance()
                let word = readWord()
                if word == "prefix" {
                    tokens.append(.prefixDecl)
                } else if word == "base" {
                    tokens.append(.baseDecl)
                } else {
                    tokens.append(.langTag(word))
                }
            case "_":
                if peek(offset: 1) == ":" {
                    advance() // _
                    advance() // :
                    let label = readLocalName()
                    tokens.append(.blankNode(label))
                } else {
                    let word = readWord()
                    tokens.append(classifyWord(word))
                }
            default:
                if ch == "+" || ch == "-" || ch.isNumber {
                    tokens.append(readNumericLiteral())
                } else if ch.isLetter || ch == ":" {
                    let word = readPrefixedNameOrWord()
                    tokens.append(word)
                } else {
                    throw TurtleDecodingError.unexpectedToken(
                        expected: "valid token",
                        found: String(ch),
                        line: line
                    )
                }
            }
        }
        tokens.append(.eof)
        return tokens
    }

    // MARK: - Read Helpers

    private func readIRI() throws -> TurtleToken {
        advance() // skip <
        var result = ""
        while index < input.endIndex && input[index] != ">" {
            if input[index] == "\n" { line += 1 }
            result.append(input[index])
            advance()
        }
        guard index < input.endIndex else {
            throw TurtleDecodingError.invalidIRI(result, line: line)
        }
        advance() // skip >
        return .iri(result)
    }

    private func readStringLiteral() throws -> TurtleToken {
        advance() // skip first "
        // Check for long string """
        if index < input.endIndex && input[index] == "\"" {
            let next = peek(offset: 1)
            if next == "\"" {
                advance() // skip second "
                advance() // skip third "
                return try readLongString()
            } else {
                // Empty string ""
                advance() // skip closing "
                return .stringLiteral("")
            }
        }
        return try readShortString()
    }

    private func readShortString() throws -> TurtleToken {
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch == "\"" {
                advance()
                return .stringLiteral(result)
            }
            if ch == "\\" {
                advance()
                guard index < input.endIndex else {
                    throw TurtleDecodingError.unterminatedString(line: line)
                }
                result.append(unescapeChar(input[index]))
                advance()
            } else {
                if ch == "\n" { line += 1 }
                result.append(ch)
                advance()
            }
        }
        throw TurtleDecodingError.unterminatedString(line: line)
    }

    private func readLongString() throws -> TurtleToken {
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch == "\"" {
                if peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
                    advance(); advance(); advance()
                    return .stringLiteral(result)
                }
            }
            if ch == "\\" {
                advance()
                guard index < input.endIndex else {
                    throw TurtleDecodingError.unterminatedString(line: line)
                }
                result.append(unescapeChar(input[index]))
                advance()
            } else {
                if ch == "\n" { line += 1 }
                result.append(ch)
                advance()
            }
        }
        throw TurtleDecodingError.unterminatedString(line: line)
    }

    private func readSingleQuotedStringLiteral() throws -> TurtleToken {
        advance() // skip first '
        if index < input.endIndex && input[index] == "'" {
            let next = peek(offset: 1)
            if next == "'" {
                advance(); advance()
                return try readLongSingleQuotedString()
            } else {
                advance()
                return .stringLiteral("")
            }
        }
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch == "'" {
                advance()
                return .stringLiteral(result)
            }
            if ch == "\\" {
                advance()
                guard index < input.endIndex else {
                    throw TurtleDecodingError.unterminatedString(line: line)
                }
                result.append(unescapeChar(input[index]))
                advance()
            } else {
                if ch == "\n" { line += 1 }
                result.append(ch)
                advance()
            }
        }
        throw TurtleDecodingError.unterminatedString(line: line)
    }

    private func readLongSingleQuotedString() throws -> TurtleToken {
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch == "'" {
                if peek(offset: 1) == "'" && peek(offset: 2) == "'" {
                    advance(); advance(); advance()
                    return .stringLiteral(result)
                }
            }
            if ch == "\\" {
                advance()
                guard index < input.endIndex else {
                    throw TurtleDecodingError.unterminatedString(line: line)
                }
                result.append(unescapeChar(input[index]))
                advance()
            } else {
                if ch == "\n" { line += 1 }
                result.append(ch)
                advance()
            }
        }
        throw TurtleDecodingError.unterminatedString(line: line)
    }

    private func readNumericLiteral() -> TurtleToken {
        var result = ""
        var hasDecimal = false
        var hasExponent = false

        // Sign
        if index < input.endIndex && (input[index] == "+" || input[index] == "-") {
            result.append(input[index])
            advance()
        }

        // Digits
        while index < input.endIndex && input[index].isNumber {
            result.append(input[index])
            advance()
        }

        // Decimal point
        if index < input.endIndex && input[index] == "." {
            let next = peek(offset: 1)
            if next != nil && next!.isNumber {
                hasDecimal = true
                result.append(input[index])
                advance()
                while index < input.endIndex && input[index].isNumber {
                    result.append(input[index])
                    advance()
                }
            }
        }

        // Exponent
        if index < input.endIndex && (input[index] == "e" || input[index] == "E") {
            hasExponent = true
            result.append(input[index])
            advance()
            if index < input.endIndex && (input[index] == "+" || input[index] == "-") {
                result.append(input[index])
                advance()
            }
            while index < input.endIndex && input[index].isNumber {
                result.append(input[index])
                advance()
            }
        }

        if hasExponent {
            return .doubleLiteral(result)
        } else if hasDecimal {
            return .decimalLiteral(result)
        } else {
            return .integerLiteral(result)
        }
    }

    private func readWord() -> String {
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
                result.append(ch)
                advance()
            } else {
                break
            }
        }
        return result
    }

    private func readLocalName() -> String {
        var result = ""
        while index < input.endIndex {
            let ch = input[index]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." {
                result.append(ch)
                advance()
            } else {
                break
            }
        }
        // Remove trailing dots (not part of local name)
        while result.hasSuffix(".") {
            result.removeLast()
            index = input.index(before: index)
        }
        return result
    }

    private func readPrefixedNameOrWord() -> TurtleToken {
        var prefix = ""
        var localName = ""
        var foundColon = false

        // Read prefix part
        while index < input.endIndex {
            let ch = input[index]
            if ch == ":" {
                foundColon = true
                advance()
                break
            } else if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
                prefix.append(ch)
                advance()
            } else {
                break
            }
        }

        if foundColon {
            // Read local name
            localName = readLocalName()
            return .prefixedName("\(prefix):\(localName)")
        } else {
            return classifyWord(prefix)
        }
    }

    private func classifyWord(_ word: String) -> TurtleToken {
        switch word {
        case "a": return .a
        case "true": return .booleanLiteral("true")
        case "false": return .booleanLiteral("false")
        case "PREFIX": return .sparqlPrefix
        case "BASE": return .sparqlBase
        default: return .prefixedName(word)
        }
    }

    private func unescapeChar(_ ch: Character) -> Character {
        switch ch {
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "\\": return "\\"
        case "\"": return "\""
        case "'": return "'"
        default: return ch
        }
    }

    // MARK: - Navigation

    private func advance() {
        index = input.index(after: index)
    }

    private func peek(offset: Int) -> Character? {
        var i = index
        for _ in 0..<offset {
            guard i < input.endIndex else { return nil }
            i = input.index(after: i)
        }
        return i < input.endIndex ? input[i] : nil
    }

    private func skipWhitespaceAndComments() {
        while index < input.endIndex {
            let ch = input[index]
            if ch == " " || ch == "\t" || ch == "\r" {
                advance()
            } else if ch == "\n" {
                line += 1
                advance()
            } else if ch == "#" {
                // Skip line comment
                while index < input.endIndex && input[index] != "\n" {
                    advance()
                }
            } else {
                break
            }
        }
    }
}

// MARK: - Parser

private final class TurtleParser {
    let tokens: [TurtleToken]
    var pos: Int = 0
    var prefixes: [String: String] = [:]
    var baseIRI: String?
    var triples: [RDFTripleRaw] = []
    var blankNodeCounter: Int = 0

    init(tokens: [TurtleToken]) {
        self.tokens = tokens
    }

    func parse() throws -> ([String: String], [RDFTripleRaw]) {
        while !isAtEnd {
            try parseStatement()
        }
        return (prefixes, triples)
    }

    // MARK: - Statement Parsing

    private func parseStatement() throws {
        switch current {
        case .prefixDecl:
            try parsePrefixDirective()
        case .sparqlPrefix:
            try parseSPARQLPrefix()
        case .baseDecl:
            try parseBaseDirective()
        case .sparqlBase:
            try parseSPARQLBase()
        case .eof:
            return
        default:
            try parseTriples()
        }
    }

    private func parsePrefixDirective() throws {
        advance() // @prefix
        guard case .prefixedName(let name) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "prefix name", found: tokenDescription(current), line: currentLine)
        }
        let prefix = String(name.dropLast()) // remove trailing ":"
        advance()
        guard case .iri(let namespace) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "IRI", found: tokenDescription(current), line: currentLine)
        }
        advance()
        try expect(.dot)
        prefixes[prefix] = namespace
    }

    private func parseSPARQLPrefix() throws {
        advance() // PREFIX
        guard case .prefixedName(let name) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "prefix name", found: tokenDescription(current), line: currentLine)
        }
        let prefix = String(name.dropLast()) // remove ":"
        advance()
        guard case .iri(let namespace) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "IRI", found: tokenDescription(current), line: currentLine)
        }
        advance()
        // SPARQL-style PREFIX does not require a dot
        prefixes[prefix] = namespace
    }

    private func parseBaseDirective() throws {
        advance() // @base
        guard case .iri(let base) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "IRI", found: tokenDescription(current), line: currentLine)
        }
        advance()
        try expect(.dot)
        baseIRI = base
    }

    private func parseSPARQLBase() throws {
        advance() // BASE
        guard case .iri(let base) = current else {
            throw TurtleDecodingError.unexpectedToken(expected: "IRI", found: tokenDescription(current), line: currentLine)
        }
        advance()
        baseIRI = base
    }

    // MARK: - Triple Parsing

    private func parseTriples() throws {
        let subject = try parseSubject()
        try parsePredicateObjectList(subject: subject)
        try expect(.dot)
    }

    private func parseSubject() throws -> RDFNode {
        switch current {
        case .iri(let iri):
            advance()
            return .iri(resolveIRI(iri))
        case .prefixedName(let name):
            advance()
            return .iri(try expandPrefixed(name))
        case .blankNode(let label):
            advance()
            return .blankNode(label)
        case .openBracket:
            return try parseBlankNodePropertyList()
        case .openParen:
            return try parseCollection()
        default:
            throw TurtleDecodingError.unexpectedToken(
                expected: "subject",
                found: tokenDescription(current),
                line: currentLine
            )
        }
    }

    private func parsePredicateObjectList(subject: RDFNode) throws {
        try parseVerbObjectList(subject: subject)
        while case .semicolon = current {
            advance() // ;
            // Allow trailing semicolons before dot
            if case .dot = current { break }
            if case .closeBracket = current { break }
            if case .eof = current { break }
            try parseVerbObjectList(subject: subject)
        }
    }

    private func parseVerbObjectList(subject: RDFNode) throws {
        let predicate = try parsePredicate()
        try parseObjectList(subject: subject, predicate: predicate)
    }

    private func parsePredicate() throws -> RDFNode {
        switch current {
        case .a:
            advance()
            return .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
        case .iri(let iri):
            advance()
            return .iri(resolveIRI(iri))
        case .prefixedName(let name):
            advance()
            return .iri(try expandPrefixed(name))
        default:
            throw TurtleDecodingError.unexpectedToken(
                expected: "predicate",
                found: tokenDescription(current),
                line: currentLine
            )
        }
    }

    private func parseObjectList(subject: RDFNode, predicate: RDFNode) throws {
        let obj = try parseObject()
        triples.append(RDFTripleRaw(subject: subject, predicate: predicate, object: obj))
        while case .comma = current {
            advance() // ,
            let obj = try parseObject()
            triples.append(RDFTripleRaw(subject: subject, predicate: predicate, object: obj))
        }
    }

    private func parseObject() throws -> RDFNode {
        switch current {
        case .iri(let iri):
            advance()
            return .iri(resolveIRI(iri))
        case .prefixedName(let name):
            advance()
            return .iri(try expandPrefixed(name))
        case .blankNode(let label):
            advance()
            return .blankNode(label)
        case .openBracket:
            return try parseBlankNodePropertyList()
        case .openParen:
            return try parseCollection()
        case .stringLiteral(let value):
            advance()
            return try parseLiteralRest(lexicalForm: value)
        case .integerLiteral(let value):
            advance()
            return .literal(OWLLiteral.integer(Int(value) ?? 0))
        case .decimalLiteral(let value):
            advance()
            return .literal(OWLLiteral.decimal(Double(value) ?? 0))
        case .doubleLiteral(let value):
            advance()
            return .literal(OWLLiteral.double(Double(value) ?? 0))
        case .booleanLiteral(let value):
            advance()
            return .literal(OWLLiteral.boolean(value == "true"))
        case .a:
            advance()
            return .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
        default:
            throw TurtleDecodingError.unexpectedToken(
                expected: "object",
                found: tokenDescription(current),
                line: currentLine
            )
        }
    }

    private func parseLiteralRest(lexicalForm: String) throws -> RDFNode {
        if case .hatHat = current {
            advance() // ^^
            let datatypeIRI: String
            switch current {
            case .iri(let iri):
                datatypeIRI = resolveIRI(iri)
                advance()
            case .prefixedName(let name):
                datatypeIRI = try expandPrefixed(name)
                advance()
            default:
                throw TurtleDecodingError.unexpectedToken(
                    expected: "datatype IRI",
                    found: tokenDescription(current),
                    line: currentLine
                )
            }
            return .literal(OWLLiteral.typed(lexicalForm, datatype: compactIRI(datatypeIRI)))
        } else if case .langTag(let lang) = current {
            advance()
            return .literal(OWLLiteral.langString(lexicalForm, language: lang))
        } else {
            return .literal(OWLLiteral.string(lexicalForm))
        }
    }

    // MARK: - Blank Node Property List

    private func parseBlankNodePropertyList() throws -> RDFNode {
        advance() // [
        let bnode = freshBlankNode()
        // Handle empty blank node []
        if case .closeBracket = current {
            advance()
            return bnode
        }
        try parsePredicateObjectList(subject: bnode)
        try expect(.closeBracket)
        return bnode
    }

    // MARK: - Collection

    private func parseCollection() throws -> RDFNode {
        advance() // (
        var items: [RDFNode] = []
        while true {
            if case .closeParen = current {
                advance()
                break
            }
            items.append(try parseObject())
        }

        if items.isEmpty {
            return .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
        }

        let rdfFirst = RDFNode.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#first")
        let rdfRest = RDFNode.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest")
        let rdfNil = RDFNode.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")

        var head: RDFNode?
        var prev: RDFNode?

        for item in items {
            let node = freshBlankNode()
            if head == nil { head = node }
            triples.append(RDFTripleRaw(subject: node, predicate: rdfFirst, object: item))
            if let p = prev {
                triples.append(RDFTripleRaw(subject: p, predicate: rdfRest, object: node))
            }
            prev = node
        }
        if let p = prev {
            triples.append(RDFTripleRaw(subject: p, predicate: rdfRest, object: rdfNil))
        }

        return head ?? rdfNil
    }

    // MARK: - Helpers

    private func expandPrefixed(_ name: String) throws -> String {
        guard let colonIdx = name.firstIndex(of: ":") else {
            return name
        }
        let prefix = String(name[name.startIndex..<colonIdx])
        let local = String(name[name.index(after: colonIdx)...])
        guard let namespace = prefixes[prefix] else {
            throw TurtleDecodingError.undefinedPrefix(prefix, line: currentLine)
        }
        return namespace + local
    }

    private func resolveIRI(_ iri: String) -> String {
        if let base = baseIRI, !iri.contains("://") {
            return base + iri
        }
        return iri
    }

    private func compactIRI(_ fullIRI: String) -> String {
        for (prefix, namespace) in prefixes {
            if fullIRI.hasPrefix(namespace) {
                let local = String(fullIRI.dropFirst(namespace.count))
                return "\(prefix):\(local)"
            }
        }
        return fullIRI
    }

    private func freshBlankNode() -> RDFNode {
        blankNodeCounter += 1
        return .blankNode("_b\(blankNodeCounter)")
    }

    private var current: TurtleToken {
        pos < tokens.count ? tokens[pos] : .eof
    }

    private var isAtEnd: Bool {
        if case .eof = current { return true }
        return false
    }

    private var currentLine: Int {
        // Approximate line from position
        return 0
    }

    private func advance() {
        pos += 1
    }

    private func expect(_ expected: TurtleToken) throws {
        if tokenMatches(current, expected) {
            advance()
        } else {
            throw TurtleDecodingError.unexpectedToken(
                expected: tokenDescription(expected),
                found: tokenDescription(current),
                line: currentLine
            )
        }
    }

    private func tokenMatches(_ a: TurtleToken, _ b: TurtleToken) -> Bool {
        switch (a, b) {
        case (.dot, .dot), (.semicolon, .semicolon), (.comma, .comma),
             (.openBracket, .openBracket), (.closeBracket, .closeBracket),
             (.openParen, .openParen), (.closeParen, .closeParen),
             (.hatHat, .hatHat), (.a, .a), (.eof, .eof),
             (.prefixDecl, .prefixDecl), (.baseDecl, .baseDecl),
             (.sparqlPrefix, .sparqlPrefix), (.sparqlBase, .sparqlBase):
            return true
        default:
            return false
        }
    }

    private func tokenDescription(_ token: TurtleToken) -> String {
        switch token {
        case .prefixDecl: return "@prefix"
        case .baseDecl: return "@base"
        case .sparqlPrefix: return "PREFIX"
        case .sparqlBase: return "BASE"
        case .iri(let v): return "<\(v)>"
        case .prefixedName(let v): return v
        case .blankNode(let v): return "_:\(v)"
        case .stringLiteral(let v): return "\"\(v)\""
        case .integerLiteral(let v): return v
        case .decimalLiteral(let v): return v
        case .doubleLiteral(let v): return v
        case .booleanLiteral(let v): return v
        case .a: return "a"
        case .dot: return "."
        case .semicolon: return ";"
        case .comma: return ","
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .openParen: return "("
        case .closeParen: return ")"
        case .hatHat: return "^^"
        case .langTag(let v): return "@\(v)"
        case .eof: return "EOF"
        }
    }
}

// MARK: - RDF Triple

private struct RDFTripleRaw {
    let subject: RDFNode
    let predicate: RDFNode
    let object: RDFNode
}

private enum RDFNode: Hashable {
    case iri(String)
    case literal(OWLLiteral)
    case blankNode(String)

    var iriValue: String? {
        if case .iri(let v) = self { return v }
        return nil
    }

    var literalValue: OWLLiteral? {
        if case .literal(let v) = self { return v }
        return nil
    }

    var blankNodeID: String? {
        if case .blankNode(let v) = self { return v }
        return nil
    }
}

// MARK: - OWL Builder

private final class OWLBuilder {

    // Well-known IRIs
    private static let rdfType = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    private static let rdfFirst = "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
    private static let rdfRest = "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
    private static let rdfNil = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
    private static let rdfsSubClassOf = "http://www.w3.org/2000/01/rdf-schema#subClassOf"
    private static let rdfsSubPropertyOf = "http://www.w3.org/2000/01/rdf-schema#subPropertyOf"
    private static let rdfsLabel = "http://www.w3.org/2000/01/rdf-schema#label"
    private static let rdfsComment = "http://www.w3.org/2000/01/rdf-schema#comment"
    private static let rdfsDomain = "http://www.w3.org/2000/01/rdf-schema#domain"
    private static let rdfsRange = "http://www.w3.org/2000/01/rdf-schema#range"
    private static let owlClass = "http://www.w3.org/2002/07/owl#Class"
    private static let owlObjectProperty = "http://www.w3.org/2002/07/owl#ObjectProperty"
    private static let owlDatatypeProperty = "http://www.w3.org/2002/07/owl#DatatypeProperty"
    private static let owlAnnotationProperty = "http://www.w3.org/2002/07/owl#AnnotationProperty"
    private static let owlNamedIndividual = "http://www.w3.org/2002/07/owl#NamedIndividual"
    private static let owlOntology = "http://www.w3.org/2002/07/owl#Ontology"
    private static let owlThing = "http://www.w3.org/2002/07/owl#Thing"
    private static let owlNothing = "http://www.w3.org/2002/07/owl#Nothing"
    private static let owlRestriction = "http://www.w3.org/2002/07/owl#Restriction"
    private static let owlEquivalentClass = "http://www.w3.org/2002/07/owl#equivalentClass"
    private static let owlInverseOf = "http://www.w3.org/2002/07/owl#inverseOf"
    private static let owlOnProperty = "http://www.w3.org/2002/07/owl#onProperty"
    private static let owlSomeValuesFrom = "http://www.w3.org/2002/07/owl#someValuesFrom"
    private static let owlAllValuesFrom = "http://www.w3.org/2002/07/owl#allValuesFrom"
    private static let owlHasValue = "http://www.w3.org/2002/07/owl#hasValue"
    private static let owlHasSelf = "http://www.w3.org/2002/07/owl#hasSelf"
    private static let owlMinCardinality = "http://www.w3.org/2002/07/owl#minCardinality"
    private static let owlMaxCardinality = "http://www.w3.org/2002/07/owl#maxCardinality"
    private static let owlCardinality = "http://www.w3.org/2002/07/owl#cardinality"
    private static let owlMinQualifiedCardinality = "http://www.w3.org/2002/07/owl#minQualifiedCardinality"
    private static let owlMaxQualifiedCardinality = "http://www.w3.org/2002/07/owl#maxQualifiedCardinality"
    private static let owlQualifiedCardinality = "http://www.w3.org/2002/07/owl#qualifiedCardinality"
    private static let owlOnClass = "http://www.w3.org/2002/07/owl#onClass"
    private static let owlOnDataRange = "http://www.w3.org/2002/07/owl#onDataRange"
    private static let owlIntersectionOf = "http://www.w3.org/2002/07/owl#intersectionOf"
    private static let owlUnionOf = "http://www.w3.org/2002/07/owl#unionOf"
    private static let owlComplementOf = "http://www.w3.org/2002/07/owl#complementOf"
    private static let owlOneOf = "http://www.w3.org/2002/07/owl#oneOf"
    private static let owlMembers = "http://www.w3.org/2002/07/owl#members"
    private static let owlDistinctMembers = "http://www.w3.org/2002/07/owl#distinctMembers"
    private static let owlDisjointUnionOf = "http://www.w3.org/2002/07/owl#disjointUnionOf"
    private static let owlPropertyChainAxiom = "http://www.w3.org/2002/07/owl#propertyChainAxiom"
    private static let owlEquivalentProperty = "http://www.w3.org/2002/07/owl#equivalentProperty"
    private static let owlSameAs = "http://www.w3.org/2002/07/owl#sameAs"
    private static let owlVersionIRI = "http://www.w3.org/2002/07/owl#versionIRI"
    private static let owlImports = "http://www.w3.org/2002/07/owl#imports"
    private static let owlAllDisjointClasses = "http://www.w3.org/2002/07/owl#AllDisjointClasses"
    private static let owlAllDifferent = "http://www.w3.org/2002/07/owl#AllDifferent"
    private static let owlAllDisjointProperties = "http://www.w3.org/2002/07/owl#AllDisjointProperties"
    private static let owlFunctionalProperty = "http://www.w3.org/2002/07/owl#FunctionalProperty"
    private static let owlInverseFunctionalProperty = "http://www.w3.org/2002/07/owl#InverseFunctionalProperty"
    private static let owlTransitiveProperty = "http://www.w3.org/2002/07/owl#TransitiveProperty"
    private static let owlSymmetricProperty = "http://www.w3.org/2002/07/owl#SymmetricProperty"
    private static let owlAsymmetricProperty = "http://www.w3.org/2002/07/owl#AsymmetricProperty"
    private static let owlReflexiveProperty = "http://www.w3.org/2002/07/owl#ReflexiveProperty"
    private static let owlIrreflexiveProperty = "http://www.w3.org/2002/07/owl#IrreflexiveProperty"

    let prefixes: [String: String]
    let triples: [RDFTripleRaw]

    /// Subject → triples index for fast lookup
    private var subjectIndex: [RDFNode: [RDFTripleRaw]] = [:]

    init(prefixes: [String: String], triples: [RDFTripleRaw]) {
        self.prefixes = prefixes
        self.triples = triples
        for triple in triples {
            subjectIndex[triple.subject, default: []].append(triple)
        }
    }

    func build() -> OWLOntology {
        let prefixMap = PrefixMap(fromOntologyPrefixes: prefixes)

        // Find ontology IRI
        var ontologyIRI = ""
        var versionIRI: String?
        var imports: [String] = []

        for triple in triples {
            if triple.predicate.iriValue == Self.rdfType && triple.object.iriValue == Self.owlOntology {
                if let iri = triple.subject.iriValue {
                    ontologyIRI = iri
                }
            }
        }

        // Ontology metadata
        for triple in subjectIndex[.iri(ontologyIRI)] ?? [] {
            if triple.predicate.iriValue == Self.owlVersionIRI, let v = triple.object.iriValue {
                versionIRI = v
            }
            if triple.predicate.iriValue == Self.owlImports, let v = triple.object.iriValue {
                imports.append(v)
            }
        }

        var classes: [OWLClass] = []
        var objectProperties: [OWLObjectProperty] = []
        var dataProperties: [OWLDataProperty] = []
        var annotationProperties: [OWLAnnotationProperty] = []
        var individuals: [OWLNamedIndividual] = []
        var axioms: [OWLAxiom] = []

        // Classify entities by rdf:type
        var classIRIs = Set<String>()
        var objPropIRIs = Set<String>()
        var dataPropIRIs = Set<String>()
        var annPropIRIs = Set<String>()
        var individualIRIs = Set<String>()
        var restrictionBNodes = Set<String>()
        var disjointClassBNodes = Set<String>()
        var allDifferentBNodes = Set<String>()
        var allDisjointPropBNodes = Set<String>()

        // Property characteristics collected from rdf:type
        var propCharacteristics: [String: Set<PropertyCharacteristic>] = [:]

        for triple in triples {
            guard triple.predicate.iriValue == Self.rdfType else { continue }
            guard let typeIRI = triple.object.iriValue else { continue }

            switch typeIRI {
            case Self.owlClass:
                if let iri = triple.subject.iriValue { classIRIs.insert(iri) }
            case Self.owlObjectProperty:
                if let iri = triple.subject.iriValue { objPropIRIs.insert(iri) }
            case Self.owlDatatypeProperty:
                if let iri = triple.subject.iriValue { dataPropIRIs.insert(iri) }
            case Self.owlAnnotationProperty:
                if let iri = triple.subject.iriValue { annPropIRIs.insert(iri) }
            case Self.owlNamedIndividual:
                if let iri = triple.subject.iriValue { individualIRIs.insert(iri) }
            case Self.owlRestriction:
                if let bnode = triple.subject.blankNodeID { restrictionBNodes.insert(bnode) }
            case Self.owlAllDisjointClasses:
                if let bnode = triple.subject.blankNodeID { disjointClassBNodes.insert(bnode) }
            case Self.owlAllDifferent:
                if let bnode = triple.subject.blankNodeID { allDifferentBNodes.insert(bnode) }
            case Self.owlAllDisjointProperties:
                if let bnode = triple.subject.blankNodeID { allDisjointPropBNodes.insert(bnode) }
            case Self.owlFunctionalProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.functional)
                }
            case Self.owlInverseFunctionalProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.inverseFunctional)
                }
            case Self.owlTransitiveProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.transitive)
                }
            case Self.owlSymmetricProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.symmetric)
                }
            case Self.owlAsymmetricProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.asymmetric)
                }
            case Self.owlReflexiveProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.reflexive)
                }
            case Self.owlIrreflexiveProperty:
                if let iri = triple.subject.iriValue {
                    propCharacteristics[iri, default: []].insert(.irreflexive)
                }
            default:
                // Type assertions for individuals (non-OWL types)
                if let iri = triple.subject.iriValue, individualIRIs.contains(iri) || (!classIRIs.contains(iri) && !objPropIRIs.contains(iri) && !dataPropIRIs.contains(iri)) {
                    // Will handle in individual processing
                }
            }
        }

        // Build classes
        for iri in classIRIs.sorted() {
            let compactedIRI = prefixMap.compact(iri)
            var label: String?
            var comment: String?
            for triple in subjectIndex[.iri(iri)] ?? [] {
                if triple.predicate.iriValue == Self.rdfsLabel, let lit = triple.object.literalValue {
                    label = lit.lexicalForm
                }
                if triple.predicate.iriValue == Self.rdfsComment, let lit = triple.object.literalValue {
                    comment = lit.lexicalForm
                }
            }
            classes.append(OWLClass(iri: compactedIRI, label: label, comment: comment))
        }

        // Build object properties
        for iri in objPropIRIs.sorted() {
            let compactedIRI = prefixMap.compact(iri)
            var label: String?
            var comment: String?
            var inverseOf: String?
            var domains: [OWLClassExpression] = []
            var ranges: [OWLClassExpression] = []

            for triple in subjectIndex[.iri(iri)] ?? [] {
                switch triple.predicate.iriValue {
                case Self.rdfsLabel:
                    if let lit = triple.object.literalValue { label = lit.lexicalForm }
                case Self.rdfsComment:
                    if let lit = triple.object.literalValue { comment = lit.lexicalForm }
                case Self.owlInverseOf:
                    if let inv = triple.object.iriValue { inverseOf = prefixMap.compact(inv) }
                case Self.rdfsDomain:
                    domains.append(buildClassExpression(from: triple.object, prefixMap: prefixMap))
                case Self.rdfsRange:
                    ranges.append(buildClassExpression(from: triple.object, prefixMap: prefixMap))
                default: break
                }
            }

            objectProperties.append(OWLObjectProperty(
                iri: compactedIRI,
                label: label,
                comment: comment,
                characteristics: propCharacteristics[iri] ?? [],
                inverseOf: inverseOf,
                domains: domains,
                ranges: ranges
            ))
        }

        // Build data properties
        for iri in dataPropIRIs.sorted() {
            let compactedIRI = prefixMap.compact(iri)
            var label: String?
            var comment: String?
            var domains: [OWLClassExpression] = []
            var ranges: [OWLDataRange] = []
            let isFunctional = propCharacteristics[iri]?.contains(.functional) ?? false

            for triple in subjectIndex[.iri(iri)] ?? [] {
                switch triple.predicate.iriValue {
                case Self.rdfsLabel:
                    if let lit = triple.object.literalValue { label = lit.lexicalForm }
                case Self.rdfsComment:
                    if let lit = triple.object.literalValue { comment = lit.lexicalForm }
                case Self.rdfsDomain:
                    domains.append(buildClassExpression(from: triple.object, prefixMap: prefixMap))
                case Self.rdfsRange:
                    ranges.append(buildDataRange(from: triple.object, prefixMap: prefixMap))
                default: break
                }
            }

            dataProperties.append(OWLDataProperty(
                iri: compactedIRI,
                label: label,
                comment: comment,
                domains: domains,
                ranges: ranges,
                isFunctional: isFunctional
            ))
        }

        // Build annotation properties
        for iri in annPropIRIs.sorted() {
            let compactedIRI = prefixMap.compact(iri)
            var label: String?
            for triple in subjectIndex[.iri(iri)] ?? [] {
                if triple.predicate.iriValue == Self.rdfsLabel, let lit = triple.object.literalValue {
                    label = lit.lexicalForm
                }
            }
            annotationProperties.append(OWLAnnotationProperty(iri: compactedIRI, label: label))
        }

        // Build individuals
        for iri in individualIRIs.sorted() {
            let compactedIRI = prefixMap.compact(iri)
            var label: String?
            var comment: String?
            for triple in subjectIndex[.iri(iri)] ?? [] {
                if triple.predicate.iriValue == Self.rdfsLabel, let lit = triple.object.literalValue {
                    label = lit.lexicalForm
                }
                if triple.predicate.iriValue == Self.rdfsComment, let lit = triple.object.literalValue {
                    comment = lit.lexicalForm
                }
            }
            individuals.append(OWLNamedIndividual(iri: compactedIRI, label: label, comment: comment))
        }

        // Build axioms from triples
        for iri in classIRIs {
            let compactedIRI = prefixMap.compact(iri)
            for triple in subjectIndex[.iri(iri)] ?? [] {
                switch triple.predicate.iriValue {
                case Self.rdfsSubClassOf:
                    let sup = buildClassExpression(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.subClassOf(sub: .named(compactedIRI), sup: sup))
                case Self.owlEquivalentClass:
                    let equiv = buildClassExpression(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.equivalentClasses([.named(compactedIRI), equiv]))
                case Self.owlDisjointUnionOf:
                    let members = collectList(from: triple.object).compactMap { node -> OWLClassExpression? in
                        buildClassExpression(from: node, prefixMap: prefixMap)
                    }
                    axioms.append(.disjointUnion(class_: compactedIRI, disjuncts: members))
                default: break
                }
            }
        }

        // Object property axioms
        for iri in objPropIRIs {
            let compactedIRI = prefixMap.compact(iri)
            for triple in subjectIndex[.iri(iri)] ?? [] {
                switch triple.predicate.iriValue {
                case Self.rdfsSubPropertyOf:
                    if let sup = triple.object.iriValue {
                        axioms.append(.subObjectPropertyOf(sub: compactedIRI, sup: prefixMap.compact(sup)))
                    }
                case Self.owlInverseOf:
                    if let inv = triple.object.iriValue {
                        axioms.append(.inverseObjectProperties(first: compactedIRI, second: prefixMap.compact(inv)))
                    }
                case Self.owlPropertyChainAxiom:
                    let chain = collectList(from: triple.object).compactMap { $0.iriValue }.map { prefixMap.compact($0) }
                    axioms.append(.subPropertyChainOf(chain: chain, sup: compactedIRI))
                case Self.owlEquivalentProperty:
                    if let eq = triple.object.iriValue {
                        axioms.append(.equivalentObjectProperties([compactedIRI, prefixMap.compact(eq)]))
                    }
                case Self.rdfsDomain:
                    let domain = buildClassExpression(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.objectPropertyDomain(property: compactedIRI, domain: domain))
                case Self.rdfsRange:
                    let range = buildClassExpression(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.objectPropertyRange(property: compactedIRI, range: range))
                default: break
                }
            }

            // Property characteristics as axioms
            if let chars = propCharacteristics[iri] {
                for char in chars {
                    switch char {
                    case .functional: axioms.append(.functionalObjectProperty(compactedIRI))
                    case .inverseFunctional: axioms.append(.inverseFunctionalObjectProperty(compactedIRI))
                    case .transitive: axioms.append(.transitiveObjectProperty(compactedIRI))
                    case .symmetric: axioms.append(.symmetricObjectProperty(compactedIRI))
                    case .asymmetric: axioms.append(.asymmetricObjectProperty(compactedIRI))
                    case .reflexive: axioms.append(.reflexiveObjectProperty(compactedIRI))
                    case .irreflexive: axioms.append(.irreflexiveObjectProperty(compactedIRI))
                    }
                }
            }
        }

        // Data property axioms
        for iri in dataPropIRIs {
            let compactedIRI = prefixMap.compact(iri)
            for triple in subjectIndex[.iri(iri)] ?? [] {
                switch triple.predicate.iriValue {
                case Self.rdfsSubPropertyOf:
                    if let sup = triple.object.iriValue {
                        axioms.append(.subDataPropertyOf(sub: compactedIRI, sup: prefixMap.compact(sup)))
                    }
                case Self.owlEquivalentProperty:
                    if let eq = triple.object.iriValue {
                        axioms.append(.equivalentDataProperties([compactedIRI, prefixMap.compact(eq)]))
                    }
                case Self.rdfsDomain:
                    let domain = buildClassExpression(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.dataPropertyDomain(property: compactedIRI, domain: domain))
                case Self.rdfsRange:
                    let range = buildDataRange(from: triple.object, prefixMap: prefixMap)
                    axioms.append(.dataPropertyRange(property: compactedIRI, range: range))
                default: break
                }
            }
            if propCharacteristics[iri]?.contains(.functional) == true {
                axioms.append(.functionalDataProperty(compactedIRI))
            }
        }

        // Individual axioms
        for iri in individualIRIs {
            let compactedIRI = prefixMap.compact(iri)
            for triple in subjectIndex[.iri(iri)] ?? [] {
                guard let predIRI = triple.predicate.iriValue else { continue }

                if predIRI == Self.rdfType {
                    if let typeIRI = triple.object.iriValue, typeIRI != Self.owlNamedIndividual {
                        axioms.append(.classAssertion(individual: compactedIRI, class_: .named(prefixMap.compact(typeIRI))))
                    }
                } else if predIRI == Self.owlSameAs {
                    if let other = triple.object.iriValue {
                        axioms.append(.sameIndividual([compactedIRI, prefixMap.compact(other)]))
                    }
                } else if predIRI == Self.rdfsLabel || predIRI == Self.rdfsComment {
                    // Already handled in entity building
                } else if let lit = triple.object.literalValue {
                    axioms.append(.dataPropertyAssertion(subject: compactedIRI, property: prefixMap.compact(predIRI), value: lit))
                } else if let objIRI = triple.object.iriValue {
                    axioms.append(.objectPropertyAssertion(subject: compactedIRI, property: prefixMap.compact(predIRI), object: prefixMap.compact(objIRI)))
                }
            }
        }

        // AllDisjointClasses
        for bnode in disjointClassBNodes {
            for triple in subjectIndex[.blankNode(bnode)] ?? [] {
                if triple.predicate.iriValue == Self.owlMembers {
                    let members = collectList(from: triple.object).map { buildClassExpression(from: $0, prefixMap: prefixMap) }
                    axioms.append(.disjointClasses(members))
                }
            }
        }

        // AllDifferent
        for bnode in allDifferentBNodes {
            for triple in subjectIndex[.blankNode(bnode)] ?? [] {
                if triple.predicate.iriValue == Self.owlDistinctMembers || triple.predicate.iriValue == Self.owlMembers {
                    let members = collectList(from: triple.object).compactMap { $0.iriValue }.map { prefixMap.compact($0) }
                    axioms.append(.differentIndividuals(members))
                }
            }
        }

        // AllDisjointProperties
        for bnode in allDisjointPropBNodes {
            for triple in subjectIndex[.blankNode(bnode)] ?? [] {
                if triple.predicate.iriValue == Self.owlMembers {
                    let members = collectList(from: triple.object).compactMap { $0.iriValue }.map { prefixMap.compact($0) }
                    // Check if object or data properties
                    if let first = members.first {
                        let expanded = PrefixMap(fromOntologyPrefixes: prefixes).expand(first)
                        if objPropIRIs.contains(expanded) {
                            axioms.append(.disjointObjectProperties(members))
                        } else {
                            axioms.append(.disjointDataProperties(members))
                        }
                    }
                }
            }
        }

        return OWLOntology(
            iri: ontologyIRI,
            versionIRI: versionIRI,
            imports: imports,
            prefixes: prefixes,
            classes: classes,
            objectProperties: objectProperties,
            dataProperties: dataProperties,
            annotationProperties: annotationProperties,
            individuals: individuals,
            axioms: axioms
        )
    }

    // MARK: - Class Expression Building

    private func buildClassExpression(from node: RDFNode, prefixMap: PrefixMap) -> OWLClassExpression {
        switch node {
        case .iri(let iri):
            switch iri {
            case Self.owlThing: return .thing
            case Self.owlNothing: return .nothing
            default: return .named(prefixMap.compact(iri))
            }
        case .blankNode(let bnode):
            return buildBlankNodeExpression(bnode: bnode, prefixMap: prefixMap)
        case .literal:
            return .thing // fallback
        }
    }

    private func buildBlankNodeExpression(bnode: String, prefixMap: PrefixMap) -> OWLClassExpression {
        let triples = subjectIndex[.blankNode(bnode)] ?? []
        let types = triples.filter { $0.predicate.iriValue == Self.rdfType }.compactMap { $0.object.iriValue }

        if types.contains(Self.owlRestriction) {
            return buildRestriction(triples: triples, prefixMap: prefixMap)
        }

        // owl:intersectionOf
        for triple in triples {
            if triple.predicate.iriValue == Self.owlIntersectionOf {
                let members = collectList(from: triple.object).map { buildClassExpression(from: $0, prefixMap: prefixMap) }
                return .intersection(members)
            }
            if triple.predicate.iriValue == Self.owlUnionOf {
                let members = collectList(from: triple.object).map { buildClassExpression(from: $0, prefixMap: prefixMap) }
                return .union(members)
            }
            if triple.predicate.iriValue == Self.owlComplementOf {
                return .complement(buildClassExpression(from: triple.object, prefixMap: prefixMap))
            }
            if triple.predicate.iriValue == Self.owlOneOf {
                let members = collectList(from: triple.object).compactMap { $0.iriValue }.map { prefixMap.compact($0) }
                return .oneOf(members)
            }
        }

        return .thing // fallback
    }

    private func buildRestriction(triples: [RDFTripleRaw], prefixMap: PrefixMap) -> OWLClassExpression {
        var property: String?
        var someValuesFrom: RDFNode?
        var allValuesFrom: RDFNode?
        var hasValue: RDFNode?
        var hasSelf: Bool = false
        var minCard: Int?
        var maxCard: Int?
        var exactCard: Int?
        var minQualCard: Int?
        var maxQualCard: Int?
        var qualCard: Int?
        var onClass: RDFNode?
        var onDataRange: RDFNode?

        for triple in triples {
            switch triple.predicate.iriValue {
            case Self.owlOnProperty:
                if let iri = triple.object.iriValue { property = prefixMap.compact(iri) }
            case Self.owlSomeValuesFrom:
                someValuesFrom = triple.object
            case Self.owlAllValuesFrom:
                allValuesFrom = triple.object
            case Self.owlHasValue:
                hasValue = triple.object
            case Self.owlHasSelf:
                if triple.object.literalValue?.lexicalForm == "true" { hasSelf = true }
            case Self.owlMinCardinality:
                minCard = triple.object.literalValue?.intValue
            case Self.owlMaxCardinality:
                maxCard = triple.object.literalValue?.intValue
            case Self.owlCardinality:
                exactCard = triple.object.literalValue?.intValue
            case Self.owlMinQualifiedCardinality:
                minQualCard = triple.object.literalValue?.intValue
            case Self.owlMaxQualifiedCardinality:
                maxQualCard = triple.object.literalValue?.intValue
            case Self.owlQualifiedCardinality:
                qualCard = triple.object.literalValue?.intValue
            case Self.owlOnClass:
                onClass = triple.object
            case Self.owlOnDataRange:
                onDataRange = triple.object
            default: break
            }
        }

        guard let prop = property else { return .thing }

        if let node = someValuesFrom {
            if node.iriValue != nil || node.blankNodeID != nil {
                return .someValuesFrom(property: prop, filler: buildClassExpression(from: node, prefixMap: prefixMap))
            }
        }
        if let node = allValuesFrom {
            if node.iriValue != nil || node.blankNodeID != nil {
                return .allValuesFrom(property: prop, filler: buildClassExpression(from: node, prefixMap: prefixMap))
            }
        }
        if let node = hasValue {
            if let iri = node.iriValue {
                return .hasValue(property: prop, individual: prefixMap.compact(iri))
            }
            if let lit = node.literalValue {
                return .dataHasValue(property: prop, literal: lit)
            }
        }
        if hasSelf {
            return .hasSelf(property: prop)
        }

        if let n = minQualCard, let cls = onClass {
            return .minCardinality(property: prop, n: n, filler: buildClassExpression(from: cls, prefixMap: prefixMap))
        }
        if let n = maxQualCard, let cls = onClass {
            return .maxCardinality(property: prop, n: n, filler: buildClassExpression(from: cls, prefixMap: prefixMap))
        }
        if let n = qualCard, let cls = onClass {
            return .exactCardinality(property: prop, n: n, filler: buildClassExpression(from: cls, prefixMap: prefixMap))
        }
        if let n = minQualCard, let dr = onDataRange {
            return .dataMinCardinality(property: prop, n: n, range: buildDataRange(from: dr, prefixMap: prefixMap))
        }
        if let n = maxQualCard, let dr = onDataRange {
            return .dataMaxCardinality(property: prop, n: n, range: buildDataRange(from: dr, prefixMap: prefixMap))
        }
        if let n = qualCard, let dr = onDataRange {
            return .dataExactCardinality(property: prop, n: n, range: buildDataRange(from: dr, prefixMap: prefixMap))
        }

        if let n = minCard {
            return .minCardinality(property: prop, n: n, filler: nil)
        }
        if let n = maxCard {
            return .maxCardinality(property: prop, n: n, filler: nil)
        }
        if let n = exactCard {
            return .exactCardinality(property: prop, n: n, filler: nil)
        }

        return .thing
    }

    // MARK: - Data Range Building

    private func buildDataRange(from node: RDFNode, prefixMap: PrefixMap) -> OWLDataRange {
        switch node {
        case .iri(let iri):
            return .datatype(prefixMap.compact(iri))
        case .blankNode(let bnode):
            let triples = subjectIndex[.blankNode(bnode)] ?? []
            for triple in triples {
                if triple.predicate.iriValue == Self.owlIntersectionOf {
                    let members = collectList(from: triple.object).map { buildDataRange(from: $0, prefixMap: prefixMap) }
                    return .dataIntersectionOf(members)
                }
                if triple.predicate.iriValue == Self.owlUnionOf {
                    let members = collectList(from: triple.object).map { buildDataRange(from: $0, prefixMap: prefixMap) }
                    return .dataUnionOf(members)
                }
                if let predIRI = triple.predicate.iriValue, predIRI.hasSuffix("datatypeComplementOf") {
                    return .dataComplementOf(buildDataRange(from: triple.object, prefixMap: prefixMap))
                }
                if triple.predicate.iriValue == Self.owlOneOf {
                    let members = collectList(from: triple.object).compactMap { $0.literalValue }
                    return .dataOneOf(members)
                }
            }
            return .datatype("xsd:string")
        case .literal:
            return .datatype("xsd:string")
        }
    }

    // MARK: - RDF List Collection

    private func collectList(from node: RDFNode) -> [RDFNode] {
        var result: [RDFNode] = []
        var current = node

        while true {
            if case .iri(let iri) = current, iri == Self.rdfNil {
                break
            }
            guard case .blankNode(let bnode) = current else {
                // If it's an IRI, it might be a single-element "list" (Turtle collection)
                if case .iri = current {
                    result.append(current)
                }
                break
            }

            let triples = subjectIndex[.blankNode(bnode)] ?? []
            var first: RDFNode?
            var rest: RDFNode?

            for triple in triples {
                if triple.predicate.iriValue == Self.rdfFirst {
                    first = triple.object
                }
                if triple.predicate.iriValue == Self.rdfRest {
                    rest = triple.object
                }
            }

            if let f = first {
                result.append(f)
            }
            if let r = rest {
                current = r
            } else {
                break
            }
        }

        return result
    }
}
