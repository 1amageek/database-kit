import DatabaseTypes

extension SHACLPath: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case predicate
        case path
        case paths
    }

    private enum Kind: String, Codable {
        case predicate
        case inverse
        case sequence
        case alternative
        case zeroOrMore
        case oneOrMore
        case zeroOrOne
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .predicate:
            self = .predicate(
                try RDFPredicateIRI(
                    container.decode(String.self, forKey: .predicate)
                )
            )
        case .inverse:
            self = .inverse(
                try container.decode(SHACLPath.self, forKey: .path)
            )
        case .sequence:
            self = .sequence(
                try SHACLPathList(
                    container.decode([SHACLPath].self, forKey: .paths)
                )
            )
        case .alternative:
            self = .alternative(
                try SHACLPathList(
                    container.decode([SHACLPath].self, forKey: .paths)
                )
            )
        case .zeroOrMore:
            self = .zeroOrMore(
                try container.decode(SHACLPath.self, forKey: .path)
            )
        case .oneOrMore:
            self = .oneOrMore(
                try container.decode(SHACLPath.self, forKey: .path)
            )
        case .zeroOrOne:
            self = .zeroOrOne(
                try container.decode(SHACLPath.self, forKey: .path)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .predicate(let iri):
            try container.encode(Kind.predicate, forKey: .kind)
            try container.encode(iri.rawValue, forKey: .predicate)
        case .inverse(let path):
            try container.encode(Kind.inverse, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .sequence(let paths):
            try container.encode(Kind.sequence, forKey: .kind)
            try container.encode(paths.elements, forKey: .paths)
        case .alternative(let paths):
            try container.encode(Kind.alternative, forKey: .kind)
            try container.encode(paths.elements, forKey: .paths)
        case .zeroOrMore(let path):
            try container.encode(Kind.zeroOrMore, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .oneOrMore(let path):
            try container.encode(Kind.oneOrMore, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .zeroOrOne(let path):
            try container.encode(Kind.zeroOrOne, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
