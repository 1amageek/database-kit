extension DatabaseRDFTerm: CustomStringConvertible {
    public var description: String {
        switch self {
        case .iri(let value):
            return "<\(value)>"
        case .blankNode(let identifier):
            return "_:\(identifier)"
        case .literal(let literal):
            let lexical = Self.escapeLiteral(literal.lexicalForm)
            if let language = literal.language {
                if let direction = literal.direction {
                    return "\"\(lexical)\"@\(language)--\(direction)"
                }
                return "\"\(lexical)\"@\(language)"
            }
            return "\"\(lexical)\"^^<\(literal.datatype)>"
        case .tripleTerm(let subject, let predicate, let object):
            return "<<( \(subject) \(predicate) \(object) )>>"
        }
    }

    private static func escapeLiteral(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(character)
            }
        }
        return result
    }
}
