// RDFDataset.swift
// Graph - RDF dataset model for TriG / N-Quads I/O

import Foundation

/// RDF literal value used by dataset codecs.
///
/// `RDFTerm` keeps using `OWLLiteral` for source compatibility. This value type
/// provides a graph-oriented name and bridges to `OWLLiteral` where needed.
public struct RDFLiteral: Sendable, Hashable, Codable {
    public var lexicalForm: String
    public var datatype: String
    public var language: String?

    public init(lexicalForm: String, datatype: String = XSDDatatype.string.iri, language: String? = nil) {
        self.lexicalForm = lexicalForm
        self.datatype = datatype
        self.language = language
    }

    public init(_ literal: OWLLiteral) {
        self.lexicalForm = literal.lexicalForm
        self.datatype = literal.datatype
        self.language = literal.language
    }

    public var owlLiteral: OWLLiteral {
        OWLLiteral(lexicalForm: lexicalForm, datatype: datatype, language: language)
    }
}

extension OWLLiteral {
    public init(_ literal: RDFLiteral) {
        self.init(
            lexicalForm: literal.lexicalForm,
            datatype: literal.datatype,
            language: literal.language
        )
    }
}

extension RDFTerm {
    public static func literal(_ literal: RDFLiteral) -> RDFTerm {
        .literal(literal.owlLiteral)
    }

    public var rdfLiteral: RDFLiteral? {
        guard case .literal(let literal) = self else { return nil }
        return RDFLiteral(literal)
    }
}

/// RDF quad. `graph == nil` represents the default graph.
public struct RDFQuad: Sendable, Hashable, Codable {
    public var subject: RDFTerm
    public var predicate: RDFTerm
    public var object: RDFTerm
    public var graph: RDFTerm?

    public init(
        subject: RDFTerm,
        predicate: RDFTerm,
        object: RDFTerm,
        graph: RDFTerm? = nil
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }

    public var triple: RDFTriple {
        RDFTriple(subject: subject, predicate: predicate, object: object)
    }

    public func validate() throws {
        guard subject.isRDFSubject else {
            throw RDFDatasetValidationError.invalidSubject(subject)
        }
        guard predicate.isRDFPredicate else {
            throw RDFDatasetValidationError.invalidPredicate(predicate)
        }
        guard object.isRDFObject else {
            throw RDFDatasetValidationError.invalidObject(object)
        }
        if let graph, !graph.isRDFGraphName {
            throw RDFDatasetValidationError.invalidGraphName(graph)
        }
    }
}

/// RDF triple in the default graph.
public struct RDFTriple: Sendable, Hashable, Codable {
    public var subject: RDFTerm
    public var predicate: RDFTerm
    public var object: RDFTerm

    public init(subject: RDFTerm, predicate: RDFTerm, object: RDFTerm) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }

    public var quad: RDFQuad {
        RDFQuad(subject: subject, predicate: predicate, object: object)
    }
}

/// RDF dataset with optional base IRI, prefixes, and quads.
public struct RDFDataset: Sendable, Hashable, Codable {
    public var baseIRI: String?
    public var prefixes: [String: String]
    public var quads: [RDFQuad]

    public init(
        baseIRI: String? = nil,
        prefixes: [String: String] = [:],
        quads: [RDFQuad] = []
    ) {
        self.baseIRI = baseIRI
        self.prefixes = prefixes
        self.quads = quads
    }

    public var triples: [RDFTriple] {
        quads.filter { $0.graph == nil }.map(\.triple)
    }

    public func validate() throws {
        for quad in quads {
            try quad.validate()
        }
    }
}

public enum RDFDatasetValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSubject(RDFTerm)
    case invalidPredicate(RDFTerm)
    case invalidObject(RDFTerm)
    case invalidGraphName(RDFTerm)

    public var description: String {
        switch self {
        case .invalidSubject(let term):
            return "RDF subject must be an IRI or blank node, got \(term)"
        case .invalidPredicate(let term):
            return "RDF predicate must be an IRI, got \(term)"
        case .invalidObject(let term):
            return "RDF object must be an IRI, blank node, or literal, got \(term)"
        case .invalidGraphName(let term):
            return "RDF graph name must be an IRI or blank node, got \(term)"
        }
    }
}

extension RDFTerm {
    public var isRDFSubject: Bool {
        switch self {
        case .iri, .blankNode: return true
        case .literal: return false
        }
    }

    public var isRDFPredicate: Bool {
        switch self {
        case .iri: return true
        case .blankNode, .literal: return false
        }
    }

    public var isRDFObject: Bool {
        true
    }

    public var isRDFGraphName: Bool {
        switch self {
        case .iri, .blankNode: return true
        case .literal: return false
        }
    }
}
