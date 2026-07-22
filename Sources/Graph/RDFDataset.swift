// RDFDataset.swift
// Graph - RDF dataset model for TriG / N-Quads I/O

import DatabaseValue
import DatabaseValueCodable

/// The canonical RDF literal used by dataset codecs.
public typealias RDFLiteral = DatabaseRDFLiteral

extension DatabaseRDFTerm {
    public var rdfLiteral: DatabaseRDFLiteral? {
        guard case .literal(let literal) = self else { return nil }
        return literal
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
        try subject.validateRDFLexicalForm()
        try predicate.validateRDFLexicalForm()
        try object.validateRDFLexicalForm()
        try graph?.validateRDFLexicalForm()
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
    case invalidIRI(String)
    case invalidBlankNodeIdentifier(String)
    case invalidLiteralDatatype(String)

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
        case .invalidIRI(let value):
            return "RDF IRI must be absolute: \(value)"
        case .invalidBlankNodeIdentifier(let value):
            return "RDF blank node identifier must not be empty: \(value)"
        case .invalidLiteralDatatype(let value):
            return "RDF literal datatype must be an absolute IRI: \(value)"
        }
    }
}

private extension DatabaseRDFTerm {
    func validateRDFLexicalForm() throws {
        switch self {
        case .iri(let value):
            guard DatabaseRDFIRIValidator.isAbsolute(value) else {
                throw RDFDatasetValidationError.invalidIRI(value)
            }
        case .blankNode(let identifier):
            guard !identifier.isEmpty else {
                throw RDFDatasetValidationError.invalidBlankNodeIdentifier(identifier)
            }
        case .literal(let literal):
            guard DatabaseRDFIRIValidator.isAbsolute(literal.datatype) else {
                throw RDFDatasetValidationError.invalidLiteralDatatype(
                    literal.datatype
                )
            }
        case .tripleTerm(let subject, let predicate, let object):
            try subject.validateRDFLexicalForm()
            try predicate.validateRDFLexicalForm()
            try object.validateRDFLexicalForm()
        }
    }
}

extension RDFTerm {
    public var isRDFSubject: Bool {
        switch self {
        case .iri, .blankNode: return true
        case .literal, .tripleTerm: return false
        }
    }

    public var isRDFPredicate: Bool {
        switch self {
        case .iri: return true
        case .blankNode, .literal, .tripleTerm: return false
        }
    }

    public var isRDFObject: Bool {
        switch self {
        case .iri, .blankNode, .literal:
            return true
        case .tripleTerm(let subject, let predicate, let object):
            return subject.isRDFSubject
                && predicate.isRDFPredicate
                && object.isRDFObject
        }
    }

    public var isRDFGraphName: Bool {
        switch self {
        case .iri, .blankNode: return true
        case .literal, .tripleTerm: return false
        }
    }
}
