import DatabaseValue

extension DatabaseRDFTerm: Codable {
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
            let identifier = try container.decode(String.self, forKey: .value)
            guard !identifier.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "RDF blank-node identifiers must not be empty"
                )
            }
            self = .blankNode(identifier)

        case .iri:
            try Self.reject(
                [.literal, .subject, .predicate, .object],
                in: container
            )
            let value = try container.decode(String.self, forKey: .value)
            do {
                _ = try DatabaseRDFIRI(value)
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "Invalid absolute RDF IRI"
                )
            }
            self = .iri(value)

        case .literal:
            try Self.reject(
                [.value, .subject, .predicate, .object],
                in: container
            )
            self = .literal(
                try container.decode(
                    DatabaseRDFLiteral.self,
                    forKey: .literal
                )
            )

        case .tripleTerm:
            try Self.reject([.value, .literal], in: container)
            let subject = try container.decode(
                DatabaseRDFTerm.self,
                forKey: .subject
            )
            let predicate = try container.decode(
                DatabaseRDFTerm.self,
                forKey: .predicate
            )
            let object = try container.decode(
                DatabaseRDFTerm.self,
                forKey: .object
            )
            do {
                try DatabaseRDFTermCodec.validate(
                    subject,
                    role: .subject
                )
                try DatabaseRDFTermCodec.validate(
                    predicate,
                    role: .predicate
                )
            } catch {
                throw DecodingError.dataCorruptedError(
                    forKey: .subject,
                    in: container,
                    debugDescription: "Invalid RDF quoted-triple subject or predicate"
                )
            }
            self = .tripleTerm(
                subject: subject,
                predicate: predicate,
                object: object
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .blankNode(let identifier):
            guard !identifier.isEmpty else {
                throw EncodingError.invalidValue(
                    self,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "RDF blank-node identifiers must not be empty"
                    )
                )
            }
            try container.encode(EncodedTermKind.blankNode, forKey: .kind)
            try container.encode(identifier, forKey: .value)

        case .iri(let value):
            do {
                _ = try DatabaseRDFIRI(value)
            } catch {
                throw EncodingError.invalidValue(
                    self,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "Invalid absolute RDF IRI"
                    )
                )
            }
            try container.encode(EncodedTermKind.iri, forKey: .kind)
            try container.encode(value, forKey: .value)

        case .literal(let literal):
            try container.encode(EncodedTermKind.literal, forKey: .kind)
            try container.encode(literal, forKey: .literal)

        case .tripleTerm(let subject, let predicate, let object):
            do {
                try DatabaseRDFTermCodec.validate(
                    subject,
                    role: .subject
                )
                try DatabaseRDFTermCodec.validate(
                    predicate,
                    role: .predicate
                )
            } catch {
                throw EncodingError.invalidValue(
                    self,
                    .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "Invalid RDF quoted-triple subject or predicate"
                    )
                )
            }
            try container.encode(EncodedTermKind.tripleTerm, forKey: .kind)
            try container.encode(subject, forKey: .subject)
            try container.encode(predicate, forKey: .predicate)
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
