// SHACLShape.swift
// Graph - SHACL shape definitions
//
// Reference: W3C SHACL §2 (SHACL Core)
// https://www.w3.org/TR/shacl/#shapes

import Foundation

/// SHACL Shape — a node shape or property shape
///
/// Shapes define constraints that focus nodes must satisfy.
///
/// **Example**:
/// ```swift
/// let shape: SHACLShape = .node(NodeShape(
///     iri: "ex:PersonShape",
///     targets: [.class_("ex:Person")],
///     propertyShapes: [
///         PropertyShape(
///             path: .predicate("ex:name"),
///             constraints: [.minCount(1), .datatype("xsd:string")]
///         )
///     ]
/// ))
/// ```
public enum SHACLShape: Sendable, Codable, Hashable {
    /// A node shape (sh:NodeShape)
    case node(NodeShape)

    /// A property shape (sh:PropertyShape)
    case property(PropertyShape)
}

// MARK: - SHACLShape Analysis

extension SHACLShape {
    /// The shape IRI (if named)
    public var iri: String? {
        switch self {
        case .node(let s): return s.iri
        case .property(let s): return s.iri
        }
    }

    /// Whether this shape is deactivated
    public var isDeactivated: Bool {
        switch self {
        case .node(let s): return s.deactivated
        case .property(let s): return s.deactivated
        }
    }

    /// The targets declared on this shape
    public var targets: [SHACLTarget] {
        switch self {
        case .node(let s): return s.targets
        case .property(let s): return s.targets
        }
    }

    /// The severity of this shape
    public var severity: SHACLSeverity {
        switch self {
        case .node(let s): return s.severity
        case .property(let s): return s.severity
        }
    }

    /// The messages of this shape
    public var messages: [String] {
        switch self {
        case .node(let s): return s.messages
        case .property(let s): return s.messages
        }
    }
}

// MARK: - NodeShape

/// sh:NodeShape — constraints on focus nodes
///
/// A node shape applies constraints directly to focus nodes
/// and declares property shapes that constrain property values.
///
/// Reference: W3C SHACL §2.1.1
public struct NodeShape: Sendable, Codable, Hashable {

    /// Shape IRI (nil for anonymous/blank node shapes)
    public var iri: String?

    /// Target declarations
    public var targets: [SHACLTarget]

    /// Constraints applied to focus nodes
    public var constraints: [SHACLConstraint]

    /// Property shapes (sh:property)
    public var propertyShapes: [PropertyShape]

    /// Severity level (default: .violation)
    public var severity: SHACLSeverity

    /// Human-readable messages (sh:message)
    public var messages: [String]

    /// Whether this shape is deactivated (sh:deactivated)
    public var deactivated: Bool

    public init(
        iri: String? = nil,
        targets: [SHACLTarget] = [],
        constraints: [SHACLConstraint] = [],
        propertyShapes: [PropertyShape] = [],
        severity: SHACLSeverity = .violation,
        messages: [String] = [],
        deactivated: Bool = false
    ) {
        self.iri = iri
        self.targets = targets
        self.constraints = constraints
        self.propertyShapes = propertyShapes
        self.severity = severity
        self.messages = messages
        self.deactivated = deactivated
    }
}

// MARK: - PropertyShape

/// sh:PropertyShape — constraints on property values
///
/// A property shape defines a path from a focus node to value nodes
/// and applies constraints to those value nodes.
///
/// Reference: W3C SHACL §2.1.2
public struct PropertyShape: Sendable, Codable, Hashable {

    /// Shape IRI (nil for anonymous)
    public var iri: String?

    /// Property path (sh:path) — required for property shapes
    public var path: SHACLPath

    /// Target declarations (can also be used as standalone shape)
    public var targets: [SHACLTarget]

    /// Constraints applied to value nodes
    public var constraints: [SHACLConstraint]

    /// Nested property shapes
    public var propertyShapes: [PropertyShape]

    /// Severity level (default: .violation)
    public var severity: SHACLSeverity

    /// Human-readable messages (sh:message)
    public var messages: [String]

    /// Whether this shape is deactivated (sh:deactivated)
    public var deactivated: Bool

    /// Human-readable name (sh:name)
    public var name: String?

    /// Human-readable description (sh:description)
    public var shapeDescription: String?

    /// Display order (sh:order)
    public var order: Double?

    /// Property group IRI (sh:group)
    public var group: String?

    /// Default value (sh:defaultValue)
    public var defaultValue: SHACLValue?

    public init(
        iri: String? = nil,
        path: SHACLPath,
        targets: [SHACLTarget] = [],
        constraints: [SHACLConstraint] = [],
        propertyShapes: [PropertyShape] = [],
        severity: SHACLSeverity = .violation,
        messages: [String] = [],
        deactivated: Bool = false,
        name: String? = nil,
        shapeDescription: String? = nil,
        order: Double? = nil,
        group: String? = nil,
        defaultValue: SHACLValue? = nil
    ) {
        self.iri = iri
        self.path = path
        self.targets = targets
        self.constraints = constraints
        self.propertyShapes = propertyShapes
        self.severity = severity
        self.messages = messages
        self.deactivated = deactivated
        self.name = name
        self.shapeDescription = shapeDescription
        self.order = order
        self.group = group
        self.defaultValue = defaultValue
    }
}

// MARK: - CustomStringConvertible

extension SHACLShape: CustomStringConvertible {
    public var description: String {
        switch self {
        case .node(let s):
            return "NodeShape(\(s.iri ?? "_:anon"), targets: \(s.targets.count), constraints: \(s.constraints.count), properties: \(s.propertyShapes.count))"
        case .property(let s):
            return "PropertyShape(\(s.iri ?? "_:anon"), path: \(s.path), constraints: \(s.constraints.count))"
        }
    }
}
