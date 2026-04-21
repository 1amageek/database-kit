// NQuadsCodec.swift
// Graph - N-Quads / N-Triples dataset codec

import Foundation

public struct NQuadsDecoder: Sendable {
    public init() {}

    public func decode(from input: String) throws -> RDFDataset {
        var quads: [RDFQuad] = []
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            var parser = NQuadsLineParser(input: line, line: lineNumber)
            let quad = try parser.parseQuad()
            try quad.validate()
            quads.append(quad)
        }
        return RDFDataset(quads: quads)
    }

    private func stripComment(from line: String) -> String {
        var escaped = false
        var inString = false
        var inIRI = false
        for index in line.indices {
            let ch = line[index]
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == "\"" && !inIRI {
                inString.toggle()
                continue
            }
            if ch == "<" && !inString {
                inIRI = true
                continue
            }
            if ch == ">" && inIRI {
                inIRI = false
                continue
            }
            if ch == "#" && !inString && !inIRI {
                return String(line[..<index])
            }
        }
        return line
    }
}

public struct NQuadsEncoder: Sendable {
    public init() {}

    public func encode(_ dataset: RDFDataset) throws -> String {
        try dataset.validate()
        let lines = dataset.quads
            .map(formatQuad(_:))
            .sorted()
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func formatQuad(_ quad: RDFQuad) -> String {
        var parts = [
            RDFSyntaxFormatter.formatNQuadsTerm(quad.subject),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.predicate),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.object)
        ]
        if let graph = quad.graph {
            parts.append(RDFSyntaxFormatter.formatNQuadsTerm(graph))
        }
        return parts.joined(separator: " ") + " ."
    }
}

private struct NQuadsLineParser {
    let input: String
    let line: Int
    var index: String.Index

    init(input: String, line: Int) {
        self.input = input
        self.line = line
        self.index = input.startIndex
    }

    mutating func parseQuad() throws -> RDFQuad {
        skipWhitespace()
        let subject = try parseTerm()
        skipWhitespace()
        let predicate = try parseTerm()
        skipWhitespace()
        let object = try parseTerm()
        skipWhitespace()

        let graph: RDFTerm?
        if peek() == "." {
            graph = nil
        } else {
            graph = try parseTerm()
            skipWhitespace()
        }

        guard peek() == "." else {
            throw RDFSyntaxError.unexpectedToken(expected: ".", found: currentDescription, line: line)
        }
        advance()
        skipWhitespace()
        guard isAtEnd else {
            throw RDFSyntaxError.unexpectedToken(expected: "end of line", found: currentDescription, line: line)
        }

        let quad = RDFQuad(subject: subject, predicate: predicate, object: object, graph: graph)
        do {
            try quad.validate()
        } catch {
            throw RDFSyntaxError.invalidQuad(String(describing: error), line: line)
        }
        return quad
    }

    private mutating func parseTerm() throws -> RDFTerm {
        guard !isAtEnd else {
            throw RDFSyntaxError.unexpectedEndOfInput(expected: "RDF term")
        }

        if peek() == "<" {
            return .iri(try parseIRI())
        }
        if peek() == "\"" {
            return .literal(try parseLiteral())
        }
        if input[index...].hasPrefix("_:") {
            return .blankNode(try parseBlankNode())
        }

        let token = readBareToken()
        guard !token.isEmpty else {
            throw RDFSyntaxError.invalidTerm(currentDescription, line: line)
        }
        return .iri(token)
    }

    private mutating func parseIRI() throws -> String {
        advance()
        var value = ""
        var escaped = false
        while !isAtEnd {
            let ch = input[index]
            advance()
            if escaped {
                value.append("\\")
                value.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == ">" {
                return RDFSyntaxFormatter.unescapeIRI(value)
            }
            value.append(ch)
        }
        throw RDFSyntaxError.invalidIRI(value, line: line)
    }

    private mutating func parseBlankNode() throws -> String {
        advance()
        advance()
        let id = readBareToken()
        guard !id.isEmpty else {
            throw RDFSyntaxError.invalidTerm("_:", line: line)
        }
        return id
    }

    private mutating func parseLiteral() throws -> OWLLiteral {
        advance()
        var value = ""
        var escaped = false
        while !isAtEnd {
            let ch = input[index]
            advance()
            if escaped {
                value.append("\\")
                value.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == "\"" {
                return try parseLiteralSuffix(lexicalForm: RDFSyntaxFormatter.unescapeString(value))
            }
            value.append(ch)
        }
        throw RDFSyntaxError.unterminatedString(line: line)
    }

    private mutating func parseLiteralSuffix(lexicalForm: String) throws -> OWLLiteral {
        if input[index...].hasPrefix("@") {
            advance()
            let language = readBareToken()
            guard !language.isEmpty else {
                throw RDFSyntaxError.invalidTerm("@", line: line)
            }
            return .langString(lexicalForm, language: language)
        }

        if input[index...].hasPrefix("^^") {
            advance()
            advance()
            let datatype: String
            if peek() == "<" {
                datatype = try parseIRI()
            } else {
                datatype = readBareToken()
            }
            guard !datatype.isEmpty else {
                throw RDFSyntaxError.invalidTerm("^^", line: line)
            }
            return .typed(lexicalForm, datatype: datatype)
        }

        return .string(lexicalForm)
    }

    private mutating func readBareToken() -> String {
        let start = index
        while !isAtEnd {
            let ch = input[index]
            if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" || ch == "." {
                break
            }
            advance()
        }
        return String(input[start..<index])
    }

    private mutating func skipWhitespace() {
        while !isAtEnd {
            let ch = input[index]
            if ch == " " || ch == "\t" || ch == "\r" || ch == "\n" {
                advance()
            } else {
                break
            }
        }
    }

    private mutating func advance() {
        index = input.index(after: index)
    }

    private func peek() -> Character? {
        isAtEnd ? nil : input[index]
    }

    private var isAtEnd: Bool {
        index >= input.endIndex
    }

    private var currentDescription: String {
        guard !isAtEnd else { return "EOF" }
        return String(input[index])
    }
}
