import DatabaseTypes

extension RDFTerm: @retroactive Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case literal
        case subject
        case predicate
        case object
    }

    private enum EncodedTermKind: String, Codable {
        case blankNode
        case iri
        case literal
        case tripleTerm
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(EncodedTermKind.self, forKey: .kind) {
        case .blankNode:
            try Self.reject(
                [.literal, .subject, .predicate, .object],
                in: container
            )
            do {
                self = .blankNode(
                    try RDFBlankNodeIdentifier(
                        container.decode(String.self, forKey: .value)
                    )
                )
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid RDF blank-node identifier"
                )
            }
        case .iri:
            try Self.reject(
                [.literal, .subject, .predicate, .object],
                in: container
            )
            do {
                self = .iri(
                    try RDFIRI(
                        container.decode(String.self, forKey: .value)
                    )
                )
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid absolute RDF IRI"
                )
            }
        case .literal:
            try Self.reject(
                [.value, .subject, .predicate, .object],
                in: container
            )
            self = .literal(
                try container.decode(RDFLiteral.self, forKey: .literal)
            )
        case .tripleTerm:
            try Self.reject([.value, .literal], in: container)
            let subjectTerm = try container.decode(
                RDFTerm.self,
                forKey: .subject
            )
            let predicateTerm = try container.decode(
                RDFTerm.self,
                forKey: .predicate
            )
            let subject: RDFSubject
            switch subjectTerm {
            case .iri(let value):
                subject = .iri(value)
            case .blankNode(let value):
                subject = .blankNode(value)
            case .literal, .tripleTerm:
                throw DecodingError.dataCorruptedError(
                    forKey: .subject,
                    in: container,
                    debugDescription: "RDF triple subject must be an IRI or blank node"
                )
            }
            guard case .iri(let predicateIRI) = predicateTerm else {
                throw DecodingError.dataCorruptedError(
                    forKey: .predicate,
                    in: container,
                    debugDescription: "RDF triple predicate must be an IRI"
                )
            }
            self = .tripleTerm(
                subject: subject,
                predicate: RDFPredicateIRI(predicateIRI),
                object: try container.decode(RDFTerm.self, forKey: .object)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .blankNode(let identifier):
            try container.encode(EncodedTermKind.blankNode, forKey: .kind)
            try container.encode(identifier.rawValue, forKey: .value)
        case .iri(let value):
            try container.encode(EncodedTermKind.iri, forKey: .kind)
            try container.encode(value.rawValue, forKey: .value)
        case .literal(let literal):
            try container.encode(EncodedTermKind.literal, forKey: .kind)
            try container.encode(literal, forKey: .literal)
        case .tripleTerm(let subject, let predicate, let object):
            try container.encode(EncodedTermKind.tripleTerm, forKey: .kind)
            try container.encode(subject.term, forKey: .subject)
            try container.encode(predicate.term, forKey: .predicate)
            try container.encode(object, forKey: .object)
        }
    }

    private static func reject(
        _ keys: [CodingKeys],
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws {
        for key in keys where container.contains(key) {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Field is invalid for this RDF term kind"
            )
        }
    }
}
