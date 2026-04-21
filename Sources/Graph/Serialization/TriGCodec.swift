// TriGCodec.swift
// Graph - TriG dataset codec

import Foundation

public struct TriGDecoder: Sendable {
    public init() {}

    public func decode(from input: String) throws -> RDFDataset {
        let tokenizer = TriGTokenizer(input: input)
        let tokens = try tokenizer.tokenize()
        var parser = TriGParser(tokens: tokens)
        let dataset = try parser.parse()
        try dataset.validate()
        return dataset
    }
}

public struct TriGEncoder: Sendable {
    public init() {}

    public func encode(_ dataset: RDFDataset) throws -> String {
        try dataset.validate()

        var lines: [String] = []
        for (prefix, namespace) in dataset.prefixes.sorted(by: { $0.key < $1.key }) {
            lines.append("@prefix \(prefix): <\(namespace)> .")
        }
        if let baseIRI = dataset.baseIRI {
            lines.append("@base <\(baseIRI)> .")
        }
        if !lines.isEmpty {
            lines.append("")
        }

        let grouped = Dictionary(grouping: dataset.quads, by: { $0.graph })
        let defaultQuads = grouped[nil, default: []]
        for line in defaultQuads.map({ formatTriple($0, prefixes: dataset.prefixes) }).sorted() {
            lines.append(line)
        }

        let namedGraphs = grouped.keys.compactMap { $0 }.sorted(by: compareTerms(_:_:))
        for graph in namedGraphs {
            if !lines.isEmpty, lines.last != "" {
                lines.append("")
            }
            lines.append("\(RDFSyntaxFormatter.formatTriGTerm(graph, prefixes: dataset.prefixes)) {")
            let graphQuads = grouped[graph, default: []]
                .map { formatTriple($0, prefixes: dataset.prefixes, indent: "    ") }
                .sorted()
            lines.append(contentsOf: graphQuads)
            lines.append("}")
        }

        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func formatTriple(_ quad: RDFQuad, prefixes: [String: String], indent: String = "") -> String {
        [
            indent + RDFSyntaxFormatter.formatTriGTerm(quad.subject, prefixes: prefixes),
            RDFSyntaxFormatter.formatTriGTerm(quad.predicate, prefixes: prefixes),
            RDFSyntaxFormatter.formatTriGTerm(quad.object, prefixes: prefixes)
        ].joined(separator: " ") + " ."
    }

    private func compareTerms(_ lhs: RDFTerm, _ rhs: RDFTerm) -> Bool {
        RDFSyntaxFormatter.formatNQuadsTerm(lhs) < RDFSyntaxFormatter.formatNQuadsTerm(rhs)
    }
}

private enum TriGToken: Sendable {
    case prefixDecl
    case baseDecl
    case sparqlPrefix
    case sparqlBase
    case graphKeyword
    case iri(String)
    case prefixedName(String)
    case blankNode(String)
    case stringLiteral(String)
    case integerLiteral(String)
    case decimalLiteral(String)
    case doubleLiteral(String)
    case booleanLiteral(String)
    case a
    case dot
    case semicolon
    case comma
    case openBracket
    case closeBracket
    case openParen
    case closeParen
    case openBrace
    case closeBrace
    case hatHat
    case langTag(String)
    case eof
}

private final class TriGTokenizer {
    let input: String
    var index: String.Index
    var line = 1

    init(input: String) {
        self.input = input
        self.index = input.startIndex
    }

    func tokenize() throws -> [TriGToken] {
        var tokens: [TriGToken] = []
        while index < input.endIndex {
            skipWhitespaceAndComments()
            guard index < input.endIndex else { break }

            let ch = input[index]
            switch ch {
            case "<":
                tokens.append(try readIRI())
            case "\"":
                tokens.append(try readStringLiteral(quote: "\""))
            case "'":
                tokens.append(try readStringLiteral(quote: "'"))
            case ".":
                if let next = peek(offset: 1), next.isNumber {
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
            case "{":
                advance()
                tokens.append(.openBrace)
            case "}":
                advance()
                tokens.append(.closeBrace)
            case "^":
                if peek(offset: 1) == "^" {
                    advance()
                    advance()
                    tokens.append(.hatHat)
                } else {
                    throw RDFSyntaxError.unexpectedToken(expected: "^^", found: String(ch), line: line)
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
                    advance()
                    advance()
                    tokens.append(.blankNode(readLocalName()))
                } else {
                    tokens.append(classifyWord(readWord()))
                }
            default:
                if ch == "+" || ch == "-" || ch.isNumber {
                    tokens.append(readNumericLiteral())
                } else if ch.isLetter || ch == ":" {
                    tokens.append(readPrefixedNameOrWord())
                } else {
                    throw RDFSyntaxError.unexpectedToken(expected: "valid token", found: String(ch), line: line)
                }
            }
        }
        tokens.append(.eof)
        return tokens
    }

    private func readIRI() throws -> TriGToken {
        advance()
        var result = ""
        var escaped = false
        while index < input.endIndex {
            let ch = input[index]
            advance()
            if escaped {
                result.append("\\")
                result.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == ">" {
                return .iri(RDFSyntaxFormatter.unescapeIRI(result))
            }
            if ch == "\n" { line += 1 }
            result.append(ch)
        }
        throw RDFSyntaxError.invalidIRI(result, line: line)
    }

    private func readStringLiteral(quote: Character) throws -> TriGToken {
        advance()
        var result = ""
        var escaped = false
        while index < input.endIndex {
            let ch = input[index]
            advance()
            if escaped {
                result.append("\\")
                result.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == quote {
                return .stringLiteral(RDFSyntaxFormatter.unescapeString(result))
            }
            if ch == "\n" { line += 1 }
            result.append(ch)
        }
        throw RDFSyntaxError.unterminatedString(line: line)
    }

    private func readNumericLiteral() -> TriGToken {
        var result = ""
        if input[index] == "+" || input[index] == "-" {
            result.append(input[index])
            advance()
        }

        while index < input.endIndex && input[index].isNumber {
            result.append(input[index])
            advance()
        }

        var isDecimal = false
        var isDouble = false
        if index < input.endIndex && input[index] == "." {
            if let next = peek(offset: 1), next.isNumber {
                isDecimal = true
                result.append(".")
                advance()
                while index < input.endIndex && input[index].isNumber {
                    result.append(input[index])
                    advance()
                }
            }
        }

        if index < input.endIndex && (input[index] == "e" || input[index] == "E") {
            isDouble = true
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

        if isDouble { return .doubleLiteral(result) }
        if isDecimal { return .decimalLiteral(result) }
        return .integerLiteral(result)
    }

    private func readPrefixedNameOrWord() -> TriGToken {
        let word = readWord()
        return classifyWord(word)
    }

    private func classifyWord(_ word: String) -> TriGToken {
        switch word {
        case "a": return .a
        case "true", "false": return .booleanLiteral(word)
        case "PREFIX": return .sparqlPrefix
        case "BASE": return .sparqlBase
        case "GRAPH": return .graphKeyword
        default:
            if word.contains(":") || word == ":" {
                return .prefixedName(word)
            }
            return .prefixedName(word)
        }
    }

    private func readWord() -> String {
        let start = index
        while index < input.endIndex {
            let ch = input[index]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == ":" || ch == "." || ch == "/" || ch == "#" {
                advance()
            } else {
                break
            }
        }
        return String(input[start..<index])
    }

    private func readLocalName() -> String {
        let start = index
        while index < input.endIndex {
            let ch = input[index]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == "." {
                advance()
            } else {
                break
            }
        }
        return String(input[start..<index])
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
                while index < input.endIndex && input[index] != "\n" {
                    advance()
                }
            } else {
                break
            }
        }
    }

    private func peek(offset: Int) -> Character? {
        var i = index
        for _ in 0..<offset {
            guard i < input.endIndex else { return nil }
            i = input.index(after: i)
        }
        return i < input.endIndex ? input[i] : nil
    }

    private func advance() {
        index = input.index(after: index)
    }
}

private struct TriGParser {
    let tokens: [TriGToken]
    var pos = 0
    var prefixes: [String: String] = [:]
    var baseIRI: String?
    var quads: [RDFQuad] = []
    var blankNodeCounter = 0

    mutating func parse() throws -> RDFDataset {
        while !isAtEnd {
            try parseStatement(graph: nil)
        }
        return RDFDataset(baseIRI: baseIRI, prefixes: prefixes, quads: quads)
    }

    private mutating func parseStatement(graph: RDFTerm?) throws {
        switch current {
        case .prefixDecl:
            try parsePrefixDirective()
        case .sparqlPrefix:
            try parseSPARQLPrefix()
        case .baseDecl:
            try parseBaseDirective()
        case .sparqlBase:
            try parseSPARQLBase()
        case .graphKeyword:
            try parseGraphBlock()
        case .eof, .closeBrace:
            return
        default:
            if graph == nil, startsGraphBlock {
                try parseGraphBlockWithoutKeyword()
            } else {
                try parseTriples(graph: graph)
                try expect(.dot)
            }
        }
    }

    private mutating func parsePrefixDirective() throws {
        advance()
        guard case .prefixedName(let name) = current else {
            throw unexpected("prefix name")
        }
        let prefix = String(name.dropLast())
        advance()
        guard case .iri(let namespace) = current else {
            throw unexpected("IRI")
        }
        advance()
        try expect(.dot)
        prefixes[prefix] = namespace
    }

    private mutating func parseSPARQLPrefix() throws {
        advance()
        guard case .prefixedName(let name) = current else {
            throw unexpected("prefix name")
        }
        let prefix = String(name.dropLast())
        advance()
        guard case .iri(let namespace) = current else {
            throw unexpected("IRI")
        }
        advance()
        prefixes[prefix] = namespace
    }

    private mutating func parseBaseDirective() throws {
        advance()
        guard case .iri(let base) = current else {
            throw unexpected("IRI")
        }
        advance()
        try expect(.dot)
        baseIRI = base
    }

    private mutating func parseSPARQLBase() throws {
        advance()
        guard case .iri(let base) = current else {
            throw unexpected("IRI")
        }
        advance()
        baseIRI = base
    }

    private mutating func parseGraphBlock() throws {
        advance()
        let graph = try parseGraphName()
        try expect(.openBrace)
        try parseGraphContent(graph: graph)
    }

    private mutating func parseGraphBlockWithoutKeyword() throws {
        let graph = try parseGraphName()
        try expect(.openBrace)
        try parseGraphContent(graph: graph)
    }

    private mutating func parseGraphContent(graph: RDFTerm) throws {
        while true {
            if case .closeBrace = current {
                advance()
                if case .dot = current { advance() }
                return
            }
            if case .eof = current {
                throw RDFSyntaxError.unexpectedEndOfInput(expected: "}")
            }
            try parseStatement(graph: graph)
        }
    }

    private mutating func parseTriples(graph: RDFTerm?) throws {
        let subject = try parseSubject(graph: graph)
        try parsePredicateObjectList(subject: subject, graph: graph)
    }

    private mutating func parsePredicateObjectList(subject: RDFTerm, graph: RDFTerm?) throws {
        try parseVerbObjectList(subject: subject, graph: graph)
        while case .semicolon = current {
            advance()
            if case .dot = current { break }
            if case .closeBracket = current { break }
            if case .closeBrace = current { break }
            if case .eof = current { break }
            try parseVerbObjectList(subject: subject, graph: graph)
        }
    }

    private mutating func parseVerbObjectList(subject: RDFTerm, graph: RDFTerm?) throws {
        let predicate = try parsePredicate()
        try parseObjectList(subject: subject, predicate: predicate, graph: graph)
    }

    private mutating func parseObjectList(subject: RDFTerm, predicate: RDFTerm, graph: RDFTerm?) throws {
        let object = try parseObject(graph: graph)
        quads.append(RDFQuad(subject: subject, predicate: predicate, object: object, graph: graph))
        while case .comma = current {
            advance()
            let object = try parseObject(graph: graph)
            quads.append(RDFQuad(subject: subject, predicate: predicate, object: object, graph: graph))
        }
    }

    private mutating func parseSubject(graph: RDFTerm?) throws -> RDFTerm {
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
            return try parseBlankNodePropertyList(graph: graph)
        case .openParen:
            return try parseCollection(graph: graph)
        default:
            throw unexpected("subject")
        }
    }

    private mutating func parsePredicate() throws -> RDFTerm {
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
            throw unexpected("predicate")
        }
    }

    private mutating func parseObject(graph: RDFTerm?) throws -> RDFTerm {
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
            return try parseBlankNodePropertyList(graph: graph)
        case .openParen:
            return try parseCollection(graph: graph)
        case .stringLiteral(let value):
            advance()
            return try parseLiteralRest(lexicalForm: value)
        case .integerLiteral(let value):
            advance()
            return .literal(.typed(value, datatype: XSDDatatype.integer.iri))
        case .decimalLiteral(let value):
            advance()
            return .literal(.typed(value, datatype: XSDDatatype.decimal.iri))
        case .doubleLiteral(let value):
            advance()
            return .literal(.typed(value, datatype: XSDDatatype.double.iri))
        case .booleanLiteral(let value):
            advance()
            return .literal(.boolean(value == "true"))
        case .a:
            advance()
            return .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
        default:
            throw unexpected("object")
        }
    }

    private mutating func parseLiteralRest(lexicalForm: String) throws -> RDFTerm {
        if case .hatHat = current {
            advance()
            let datatype: String
            switch current {
            case .iri(let iri):
                datatype = resolveIRI(iri)
                advance()
            case .prefixedName(let name):
                datatype = try expandPrefixed(name)
                advance()
            default:
                throw unexpected("datatype IRI")
            }
            return .literal(.typed(lexicalForm, datatype: datatype))
        }
        if case .langTag(let language) = current {
            advance()
            return .literal(.langString(lexicalForm, language: language))
        }
        return .literal(.string(lexicalForm))
    }

    private mutating func parseBlankNodePropertyList(graph: RDFTerm?) throws -> RDFTerm {
        advance()
        let blank = freshBlankNode()
        if case .closeBracket = current {
            advance()
            return blank
        }
        try parsePredicateObjectList(subject: blank, graph: graph)
        try expect(.closeBracket)
        return blank
    }

    private mutating func parseCollection(graph: RDFTerm?) throws -> RDFTerm {
        advance()
        var items: [RDFTerm] = []
        while true {
            if case .closeParen = current {
                advance()
                break
            }
            items.append(try parseObject(graph: graph))
        }

        if items.isEmpty {
            return .iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
        }

        let rdfFirst = RDFTerm.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#first")
        let rdfRest = RDFTerm.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#rest")
        let rdfNil = RDFTerm.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")

        var head: RDFTerm?
        var previous: RDFTerm?
        for item in items {
            let node = freshBlankNode()
            if head == nil { head = node }
            quads.append(RDFQuad(subject: node, predicate: rdfFirst, object: item, graph: graph))
            if let previous {
                quads.append(RDFQuad(subject: previous, predicate: rdfRest, object: node, graph: graph))
            }
            previous = node
        }
        if let previous {
            quads.append(RDFQuad(subject: previous, predicate: rdfRest, object: rdfNil, graph: graph))
        }
        return head ?? rdfNil
    }

    private mutating func parseGraphName() throws -> RDFTerm {
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
        default:
            throw unexpected("graph name")
        }
    }

    private func expandPrefixed(_ name: String) throws -> String {
        guard let colonIndex = name.firstIndex(of: ":") else {
            return name
        }
        let prefix = String(name[name.startIndex..<colonIndex])
        let local = String(name[name.index(after: colonIndex)...])
        guard let namespace = prefixes[prefix] else {
            throw RDFSyntaxError.undefinedPrefix(prefix, line: currentLine)
        }
        return namespace + local
    }

    private func resolveIRI(_ iri: String) -> String {
        if let baseIRI, !iri.contains("://") && !iri.hasPrefix("urn:") {
            return baseIRI + iri
        }
        return iri
    }

    private mutating func freshBlankNode() -> RDFTerm {
        blankNodeCounter += 1
        return .blankNode("_b\(blankNodeCounter)")
    }

    private var startsGraphBlock: Bool {
        switch current {
        case .iri, .prefixedName, .blankNode:
            if pos + 1 < tokens.count, case .openBrace = tokens[pos + 1] {
                return true
            }
            return false
        default:
            return false
        }
    }

    private var current: TriGToken {
        pos < tokens.count ? tokens[pos] : .eof
    }

    private var isAtEnd: Bool {
        if case .eof = current { return true }
        return false
    }

    private var currentLine: Int {
        0
    }

    private mutating func advance() {
        pos += 1
    }

    private mutating func expect(_ expected: TriGToken) throws {
        if tokenMatches(current, expected) {
            advance()
        } else {
            throw unexpected(tokenDescription(expected))
        }
    }

    private func unexpected(_ expected: String) -> RDFSyntaxError {
        RDFSyntaxError.unexpectedToken(
            expected: expected,
            found: tokenDescription(current),
            line: currentLine
        )
    }

    private func tokenMatches(_ lhs: TriGToken, _ rhs: TriGToken) -> Bool {
        switch (lhs, rhs) {
        case (.prefixDecl, .prefixDecl), (.baseDecl, .baseDecl),
             (.sparqlPrefix, .sparqlPrefix), (.sparqlBase, .sparqlBase),
             (.graphKeyword, .graphKeyword), (.dot, .dot),
             (.semicolon, .semicolon), (.comma, .comma),
             (.openBracket, .openBracket), (.closeBracket, .closeBracket),
             (.openParen, .openParen), (.closeParen, .closeParen),
             (.openBrace, .openBrace), (.closeBrace, .closeBrace),
             (.hatHat, .hatHat), (.a, .a), (.eof, .eof):
            return true
        default:
            return false
        }
    }

    private func tokenDescription(_ token: TriGToken) -> String {
        switch token {
        case .prefixDecl: return "@prefix"
        case .baseDecl: return "@base"
        case .sparqlPrefix: return "PREFIX"
        case .sparqlBase: return "BASE"
        case .graphKeyword: return "GRAPH"
        case .iri(let value): return "<\(value)>"
        case .prefixedName(let value): return value
        case .blankNode(let value): return "_:\(value)"
        case .stringLiteral(let value): return "\"\(value)\""
        case .integerLiteral(let value): return value
        case .decimalLiteral(let value): return value
        case .doubleLiteral(let value): return value
        case .booleanLiteral(let value): return value
        case .a: return "a"
        case .dot: return "."
        case .semicolon: return ";"
        case .comma: return ","
        case .openBracket: return "["
        case .closeBracket: return "]"
        case .openParen: return "("
        case .closeParen: return ")"
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .hatHat: return "^^"
        case .langTag(let value): return "@\(value)"
        case .eof: return "EOF"
        }
    }
}
