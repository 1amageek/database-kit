// RDFDataset.swift
// Graph - RDF dataset model for TriG / N-Quads I/O

import DatabaseTypes

extension RDFTerm {
    public var rdfLiteral: RDFLiteral? {
        guard case .literal(let literal) = self else { return nil }
        return literal
    }
}

/// RDF quad. `graph == nil` represents the default graph.
public struct RDFQuad: Sendable, Hashable {
    public var subject: RDFSubject
    public var predicate: RDFPredicateIRI
    public var object: RDFTerm
    public var graph: RDFGraphName?

    public init(
        subject: RDFSubject,
        predicate: RDFPredicateIRI,
        object: RDFTerm,
        graph: RDFGraphName? = nil
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
        self.graph = graph
    }

    public var triple: RDFTriple {
        RDFTriple(subject: subject, predicate: predicate, object: object)
    }

    package init(
        validatingSubject subject: RDFTerm,
        predicate: RDFTerm,
        object: RDFTerm,
        graph: RDFTerm? = nil
    ) throws {
        self.subject = try RDFSubject(validating: subject)
        self.predicate = try RDFPredicateIRI(validating: predicate)
        self.object = object
        self.graph = try graph.map(RDFGraphName.init)
    }

    public func validate() throws {
        try RDFTermCodec.validate(object, role: .object)
    }

}

/// RDF triple in the default graph.
public struct RDFTriple: Sendable, Hashable {
    public var subject: RDFSubject
    public var predicate: RDFPredicateIRI
    public var object: RDFTerm

    public init(
        subject: RDFSubject,
        predicate: RDFPredicateIRI,
        object: RDFTerm
    ) {
        self.subject = subject
        self.predicate = predicate
        self.object = object
    }

    public var quad: RDFQuad {
        RDFQuad(subject: subject, predicate: predicate, object: object)
    }

    package init(
        validatingSubject subject: RDFTerm,
        predicate: RDFTerm,
        object: RDFTerm
    ) throws {
        self.subject = try RDFSubject(validating: subject)
        self.predicate = try RDFPredicateIRI(validating: predicate)
        self.object = object
    }

}

/// RDF dataset with optional base IRI, prefixes, and quads.
public struct RDFDataset: Sendable, Hashable {
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
    case invalidGraphName(RDFTerm)

    public var description: String {
        switch self {
        case .invalidSubject(let term):
            return "RDF subject must be an IRI or blank node, got \(term)"
        case .invalidPredicate(let term):
            return "RDF predicate must be an IRI, got \(term)"
        case .invalidGraphName(let term):
            return "RDF graph name must be an IRI or blank node, got \(term)"
        }
    }
}

private extension RDFSubject {
    init(validating term: RDFTerm) throws {
        switch term {
        case .iri(let iri):
            self = .iri(iri)
        case .blankNode(let identifier):
            self = .blankNode(identifier)
        case .literal, .tripleTerm:
            throw RDFDatasetValidationError.invalidSubject(term)
        }
    }
}

private extension RDFPredicateIRI {
    init(validating term: RDFTerm) throws {
        guard case .iri(let iri) = term else {
            throw RDFDatasetValidationError.invalidPredicate(term)
        }
        self.init(iri)
    }
}
