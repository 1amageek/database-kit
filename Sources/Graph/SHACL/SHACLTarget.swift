// SHACLTarget.swift
// Graph - SHACL target declarations
//
// Reference: W3C SHACL §2.1.3 (Targets)
// https://www.w3.org/TR/shacl/#targets

import Foundation

/// SHACL Target — focus node selection mechanism
///
/// Targets determine which nodes in the data graph are validated against a shape.
///
/// **Example**:
/// ```swift
/// // All instances of ex:Person
/// let target: SHACLTarget = .class_("ex:Person")
///
/// // A specific node
/// let target: SHACLTarget = .node("ex:Alice")
///
/// // All subjects that have an ex:email property
/// let target: SHACLTarget = .subjectsOf("ex:email")
/// ```
public enum SHACLTarget: Sendable, Codable, Hashable {
    /// sh:targetNode — a specific node IRI
    case node(String)

    /// sh:targetClass — all instances of the given class
    case class_(String)

    /// sh:targetSubjectsOf — all subjects of triples with the given predicate
    case subjectsOf(String)

    /// sh:targetObjectsOf — all objects of triples with the given predicate
    case objectsOf(String)

    /// Implicit class target — the shape IRI itself is treated as an rdfs:Class
    case implicitClass
}

// MARK: - Analysis

extension SHACLTarget {
    /// The IRI referenced by this target (if any)
    public var referencedIRI: String? {
        switch self {
        case .node(let iri), .class_(let iri),
             .subjectsOf(let iri), .objectsOf(let iri):
            return iri
        case .implicitClass:
            return nil
        }
    }
}

// MARK: - CustomStringConvertible

extension SHACLTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .node(let iri):
            return "sh:targetNode \(iri)"
        case .class_(let iri):
            return "sh:targetClass \(iri)"
        case .subjectsOf(let iri):
            return "sh:targetSubjectsOf \(iri)"
        case .objectsOf(let iri):
            return "sh:targetObjectsOf \(iri)"
        case .implicitClass:
            return "implicit class target"
        }
    }
}
