// SHACLPath.swift
// Graph - SHACL property path expressions
//
// Reference: W3C SHACL §2.3.1 (SHACL Property Paths)
// https://www.w3.org/TR/shacl/#property-paths

import Foundation

/// SHACL Property Path
///
/// Defines the path from a focus node to value nodes.
/// SHACL paths are a subset of SPARQL 1.1 Property Paths.
///
/// **Example**:
/// ```swift
/// // Simple predicate path
/// let namePath: SHACLPath = .predicate("ex:name")
///
/// // Inverse path
/// let knownByPath: SHACLPath = .inverse(.predicate("ex:knows"))
///
/// // Sequence path (ex:parent / ex:name)
/// let parentNamePath: SHACLPath = .sequence([
///     .predicate("ex:parent"),
///     .predicate("ex:name")
/// ])
///
/// // Alternative path
/// let labelPath: SHACLPath = .alternative([
///     .predicate("rdfs:label"),
///     .predicate("skos:prefLabel")
/// ])
/// ```
public indirect enum SHACLPath: Sendable, Codable, Hashable {
    /// Direct predicate IRI (sh:path with IRI value)
    case predicate(String)

    /// Inverse path (sh:inversePath)
    case inverse(SHACLPath)

    /// Sequence path — path1 / path2 / ... (rdf:List of paths)
    case sequence([SHACLPath])

    /// Alternative path — path1 | path2 | ... (sh:alternativePath)
    case alternative([SHACLPath])

    /// Zero-or-more path — path* (sh:zeroOrMorePath)
    case zeroOrMore(SHACLPath)

    /// One-or-more path — path+ (sh:oneOrMorePath)
    case oneOrMore(SHACLPath)

    /// Zero-or-one path — path? (sh:zeroOrOnePath)
    case zeroOrOne(SHACLPath)
}

// MARK: - Analysis

extension SHACLPath {
    /// Whether this is a simple predicate path (no operators)
    public var isPredicatePath: Bool {
        if case .predicate = self { return true }
        return false
    }

    /// Extract the predicate IRI if this is a simple predicate path
    public var predicateIRI: String? {
        if case .predicate(let iri) = self { return iri }
        return nil
    }

    /// All predicate IRIs referenced in this path
    public var referencedPredicates: Set<String> {
        switch self {
        case .predicate(let iri):
            return [iri]
        case .inverse(let inner):
            return inner.referencedPredicates
        case .sequence(let paths), .alternative(let paths):
            return paths.reduce(into: Set<String>()) { $0.formUnion($1.referencedPredicates) }
        case .zeroOrMore(let inner), .oneOrMore(let inner), .zeroOrOne(let inner):
            return inner.referencedPredicates
        }
    }
}

// MARK: - CustomStringConvertible

extension SHACLPath: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let iri):
            return iri
        case .inverse(let inner):
            return "^(\(inner))"
        case .sequence(let paths):
            return paths.map(\.description).joined(separator: " / ")
        case .alternative(let paths):
            return paths.map(\.description).joined(separator: " | ")
        case .zeroOrMore(let inner):
            return "(\(inner))*"
        case .oneOrMore(let inner):
            return "(\(inner))+"
        case .zeroOrOne(let inner):
            return "(\(inner))?"
        }
    }
}
