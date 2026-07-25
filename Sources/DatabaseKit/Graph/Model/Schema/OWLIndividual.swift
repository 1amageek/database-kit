import DatabaseTypes
// OWLIndividual.swift
// Graph - OWL DL individual definitions
//
// Provides individual (instance) types for OWL DL ontologies.
//
// Reference: W3C OWL 2 Web Ontology Language
// https://www.w3.org/TR/owl2-syntax/#Individuals

/// OWL Named Individual
///
/// Represents a named individual (instance) in an OWL ontology.
/// Named individuals have an IRI that uniquely identifies them.
///
/// **Example**:
/// ```swift
/// let alice = OWLNamedIndividual(iri: "ex:Alice", label: "Alice")
/// let bob = OWLNamedIndividual(iri: "ex:Bob", label: "Bob")
/// ```
public struct OWLNamedIndividual: Sendable, Hashable {
    /// Individual IRI (identifier)
    public let iri: String

    /// Human-readable label
    public var label: String?

    /// Human-readable comment/description
    public var comment: String?

    /// Additional annotations
    public var annotations: [String: String]

    public init(
        iri: String,
        label: String? = nil,
        comment: String? = nil,
        annotations: [String: String] = [:]
    ) {
        self.iri = iri
        self.label = label
        self.comment = comment
        self.annotations = annotations
    }
}

// MARK: - Anonymous Individual

/// OWL Anonymous Individual
///
/// Represents an anonymous (blank node) individual in an OWL ontology.
/// Anonymous individuals don't have a global identifier and are
/// identified only by their internal node ID.
///
/// **Note**: Anonymous individuals are typically used for existential
/// restrictions and are handled internally by the reasoner.
///
/// **Example**:
/// ```swift
/// // Represents an anonymous individual created during reasoning
/// let anon = OWLAnonymousIndividual(nodeID: "_:b1")
/// ```
public struct OWLAnonymousIndividual: Sendable, Hashable {
    /// Internal node identifier (blank node ID)
    public let nodeID: String

    public init(nodeID: String) {
        self.nodeID = nodeID
    }

    /// Creates an anonymous individual from an application-assigned node identifier.
    public static func anonymous(nodeID: String) -> OWLAnonymousIndividual {
        OWLAnonymousIndividual(nodeID: nodeID)
    }
}

// MARK: - Individual (Union Type)

/// OWL Individual (Named or Anonymous)
///
/// Represents either a named or anonymous individual.
/// Used in contexts where both types are valid.
public enum OWLIndividual: Sendable, Hashable {
    case named(OWLNamedIndividual)
    case anonymous(OWLAnonymousIndividual)

    /// Get the identifier (IRI for named, nodeID for anonymous)
    public var identifier: String {
        switch self {
        case .named(let ind):
            return ind.iri
        case .anonymous(let ind):
            return ind.nodeID
        }
    }

    /// Check if this is a named individual
    public var isNamed: Bool {
        if case .named = self { return true }
        return false
    }

    /// Check if this is an anonymous individual
    public var isAnonymous: Bool {
        if case .anonymous = self { return true }
        return false
    }

    /// Get the named individual if this is one
    public var asNamed: OWLNamedIndividual? {
        if case .named(let ind) = self { return ind }
        return nil
    }

    /// Get the anonymous individual if this is one
    public var asAnonymous: OWLAnonymousIndividual? {
        if case .anonymous(let ind) = self { return ind }
        return nil
    }
}

// MARK: - Convenience

extension OWLIndividual {
    /// Create a named individual
    public static func named(_ iri: String) -> OWLIndividual {
        .named(OWLNamedIndividual(iri: iri))
    }

    /// Creates an anonymous individual from an application-assigned node identifier.
    public static func anonymous(nodeID: String) -> OWLIndividual {
        .anonymous(OWLAnonymousIndividual(nodeID: nodeID))
    }
}

// MARK: - CustomStringConvertible

extension OWLNamedIndividual: CustomStringConvertible {
    public var description: String {
        if let label = label {
            return "\(label) (\(iri))"
        }
        return iri
    }
}

extension OWLAnonymousIndividual: CustomStringConvertible {
    public var description: String {
        nodeID
    }
}

extension OWLIndividual: CustomStringConvertible {
    public var description: String {
        switch self {
        case .named(let ind):
            return ind.description
        case .anonymous(let ind):
            return ind.description
        }
    }
}

// MARK: - ExpressibleByStringLiteral

extension OWLNamedIndividual: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(iri: value)
    }
}
