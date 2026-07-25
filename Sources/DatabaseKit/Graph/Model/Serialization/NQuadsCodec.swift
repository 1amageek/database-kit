import DatabaseTypes
// NQuadsCodec.swift
// Graph - N-Quads / N-Triples dataset codec

public struct NQuadsDecoder: Sendable {
    public init() {}

    public func decode(
        from input: String
    ) throws(RDFSyntaxError) -> RDFDataset {
        var quads: [RDFQuad] = []
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            let line = trimASCIIWhitespace(stripComment(from: rawLine))
            guard !line.isEmpty else { continue }

            var parser = NQuadsLineParser(input: line, line: lineNumber)
            let quad = try parser.parseQuad()
            do {
                try quad.validate()
            } catch let error {
                throw .invalidDataset(error)
            }
            quads.append(quad)
        }
        return RDFDataset(quads: quads)
    }

    private func stripComment(from line: Substring) -> Substring {
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
                return line[..<index]
            }
        }
        return line
    }

    private func trimASCIIWhitespace(_ value: Substring) -> Substring {
        var lowerBound = value.startIndex
        var upperBound = value.endIndex
        while lowerBound < upperBound,
              Self.isASCIIWhitespace(value[lowerBound]) {
            lowerBound = value.index(after: lowerBound)
        }
        while lowerBound < upperBound {
            let previous = value.index(before: upperBound)
            guard Self.isASCIIWhitespace(value[previous]) else {
                break
            }
            upperBound = previous
        }
        return value[lowerBound..<upperBound]
    }

    private static func isASCIIWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
            || character == "\r" || character == "\n"
    }
}

public struct NQuadsEncoder: Sendable {
    public init() {}

    public func encode(
        _ dataset: RDFDataset
    ) throws(RDFTermCodecError) -> String {
        try dataset.validate()
        let lines = dataset.quads
            .map(formatQuad(_:))
            .sorted()
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private func formatQuad(_ quad: RDFQuad) -> String {
        var parts = [
            RDFSyntaxFormatter.formatNQuadsTerm(quad.subject.term),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.predicate.term),
            RDFSyntaxFormatter.formatNQuadsTerm(quad.object)
        ]
        if let graph = quad.graph {
            parts.append(RDFSyntaxFormatter.formatNQuadsTerm(graph.term))
        }
        return parts.joined(separator: " ") + " ."
    }
}

private struct NQuadsLineParser {
    let input: Substring
    let line: Int
    var index: String.Index

    init(input: Substring, line: Int) {
        self.input = input
        self.line = line
        self.index = input.startIndex
    }

    mutating func parseQuad() throws(RDFSyntaxError) -> RDFQuad {
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

        let quad: RDFQuad
        do {
            quad = try RDFQuad(
                validatingSubject: subject,
                predicate: predicate,
                object: object,
                graph: graph
            )
        } catch {
            throw RDFSyntaxError.invalidQuad(
                "subject, predicate, or graph term has an invalid RDF role",
                line: line
            )
        }
        do {
            try quad.validate()
            return quad
        } catch {
            throw RDFSyntaxError.invalidQuad(
                "object term violates the canonical RDF term limits",
                line: line
            )
        }
    }

    private mutating func parseTerm() throws(RDFSyntaxError) -> RDFTerm {
        guard !isAtEnd else {
            throw RDFSyntaxError.unexpectedEndOfInput(expected: "RDF term")
        }

        if peek() == "<" {
            let rawValue = try parseIRI()
            return try validatedIRI(rawValue)
        }
        if peek() == "\"" {
            return .literal(try parseLiteral())
        }
        if input[index...].hasPrefix("_:") {
            let identifier = try parseBlankNode()
            do {
                return try .blankNode(identifier: identifier)
            } catch {
                throw .invalidTerm("_:\(identifier)", line: line)
            }
        }

        let token = readBareToken()
        guard !token.isEmpty else {
            throw RDFSyntaxError.invalidTerm(currentDescription, line: line)
        }
        return try validatedIRI(token)
    }

    private mutating func parseIRI() throws(RDFSyntaxError) -> String {
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

    private mutating func parseBlankNode()
        throws(RDFSyntaxError) -> String {
        advance()
        advance()
        let id = readBareToken()
        guard !id.isEmpty else {
            throw RDFSyntaxError.invalidTerm("_:", line: line)
        }
        return id
    }

    private mutating func parseLiteral()
        throws(RDFSyntaxError) -> RDFLiteral {
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

    private mutating func parseLiteralSuffix(
        lexicalForm: String
    ) throws(RDFSyntaxError) -> RDFLiteral {
        if input[index...].hasPrefix("@") {
            advance()
            let language = readBareToken()
            guard !language.isEmpty else {
                throw RDFSyntaxError.invalidTerm("@", line: line)
            }
            do {
                return try .langString(lexicalForm, language: language)
            } catch {
                throw .invalidTerm("@\(language)", line: line)
            }
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
            do {
                return try .typed(lexicalForm, datatype: datatype)
            } catch {
                throw .invalidIRI(datatype, line: line)
            }
        }

        return .string(lexicalForm)
    }

    private func validatedIRI(
        _ rawValue: String
    ) throws(RDFSyntaxError) -> RDFTerm {
        do {
            return try .iri(validating: rawValue)
        } catch {
            throw .invalidIRI(rawValue, line: line)
        }
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
